# frozen_string_literal: true

require "nostr"

module Attestation
	# The platform's attestation identity: resolves the issuing hex key from ENV (a dedicated key, or R_op as
	# the fallback), derives its public key, and signs through the Events::Sign service. The private key is read
	# and held only here (private reader), never exposed, so an including model is a safe identity object. The
	# key is the platform's OWN, never a user key (the non-custodial invariant). Mix into a small identity model;
	# the actual signing is the Events::Sign service this delegates to.
	module IssuerIdentity
		extend ActiveSupport::Concern

		class_methods do
			# True when an issuing key is available (dedicated, or R_op as the fallback).
			def configured?
				resolved_key.present?
			end

			def resolved_key
				ENV[Attestation::KEY_ENV].presence || ENV[Attestation::FALLBACK_KEY_ENV].presence
			end
		end

		def pubkey
			@pubkey ||= keypair.public_key.to_s
		end

		def sign(kind:, content: "", tags: [], created_at: Time.now.to_i)
			Events::Sign.call(private_key:, kind:, content:, tags:, created_at:)
		end

		private

		def private_key
			key = self.class.resolved_key
			if key.blank?
				raise(KeyError, "attestation key missing (#{Attestation::KEY_ENV} or #{Attestation::FALLBACK_KEY_ENV})")
			end

			key
		end

		def keypair
			@keypair ||= Nostr::Keygen.new.get_key_pair_from_private_key(Nostr::PrivateKey.new(private_key))
		end
	end
end
