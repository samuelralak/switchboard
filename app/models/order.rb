# frozen_string_literal: true

# A manual-escrow order. State lives in the order_transitions ledger; current_state is a denormalized cache.
class Order < ApplicationRecord
	has_many :order_transitions, autosave: false, dependent: :destroy, inverse_of: :order
	has_many :effects, class_name: "OrderEffect", dependent: :destroy, inverse_of: :order
	has_many :proofs, class_name: "OrderProof", dependent: :destroy, inverse_of: :order
	has_one :lock, class_name: "OrderLock", dependent: :destroy, inverse_of: :order
	# The provider's observable delivery assertion (off the money path; current_state stays funded).
	has_one :delivery, class_name: "OrderDelivery", dependent: :destroy, inverse_of: :order
	# The consumer's observable release assertion (preimage revealed; current_state stays funded until the
	# mint confirms the spend).
	has_one :release, class_name: "OrderRelease", dependent: :destroy, inverse_of: :order

	validates :entry_point, inclusion: { in: Orders::EntryPoints::ALL }
	validates :tier, inclusion: { in: Orders::Tiers::ALL }
	validates :current_state, inclusion: { in: Orders::States::ALL }
	validates :consumer_pubkey, :provider_pubkey, presence: true, format: { with: Events::Kinds::HEX64 }
	validates :listing_coordinate, :mint_url, :dedupe_key, :funding_deadline_at, presence: true
	validates :amount_sats, numericality: { only_integer: true, greater_than: 0 }

	# Policy + invariant guards that back Orders::CreateContract, so a direct create cannot bypass them.
	validate :consumer_differs_from_provider
	validate :mint_allowlisted, on: :create
	validate :amount_within_cap, on: :create
	# current_state is written only by the state machine (via update_column, which skips this); any other
	# update that changes it must agree with the ledger head.
	validate :current_state_matches_ledger, on: :update, if: :current_state_changed?

	scope :in_state, ->(*states) { where(current_state: states.flatten) }
	scope :active, -> { in_state(Orders::States::ACTIVE) }
	scope :funding_due, -> { in_state(Orders::States::AWAITING_FUNDING).where(funding_deadline_at: ..Time.current) }

	# Party scopes: the consumer pays, the provider delivers; `involving` is either side (a viewer).
	scope :as_consumer, ->(pubkey) { where(consumer_pubkey: pubkey) }
	scope :as_provider, ->(pubkey) { where(provider_pubkey: pubkey) }
	scope :involving, ->(pubkey) { as_consumer(pubkey).or(as_provider(pubkey)) }

	def state_machine
		@state_machine ||= Orders::StateMachine.new(self, transition_class: OrderTransition)
	end

	def terminal? = Orders::States.terminal?(current_state)
	def settled? = Orders::States.settlement?(current_state)

	def tier1?
		tier == Orders::Tiers::TIER1_HTLC
	end

	def tier2?
		tier == Orders::Tiers::TIER2_ARBITER
	end

	private

	def consumer_differs_from_provider
		return if consumer_pubkey.blank? || consumer_pubkey != provider_pubkey

		errors.add(:provider_pubkey, "must differ from the consumer")
	end

	def mint_allowlisted
		errors.add(:mint_url, "not allowlisted") unless Orders::Policy.mint_allowed?(mint_url)
	end

	def amount_within_cap
		errors.add(:amount_sats, "exceeds the per-order cap") if amount_sats && amount_sats > Orders::Policy.cap_for(tier)
	end

	def current_state_matches_ledger
		return if state_machine.current_state(force_reload: true) == current_state

		errors.add(:current_state, "must change through the state machine")
	end
end
