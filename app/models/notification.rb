# frozen_string_literal: true

# A recipient-addressed in-app notification: a denormalized read-model PROJECTED from server-observable
# events (the order lifecycle), never a source of truth for them. Written by Notifications::Deliver in the
# same after_commit that broadcasts the live order update, so it stays strictly an observer. `seen_at`
# drives the bell badge (unseen count, cleared when the dropdown opens). `read_at` + the `unread` scope drive
# per-notification read tracking: a row marks itself read when opened (NotificationsController#update), and
# the unread dot keys off `read_at` (cleared per-row, independent of the seen badge).
class Notification < ApplicationRecord
	validates :recipient_pubkey, presence: true, format: { with: Events::Kinds::HEX64 }
	validates :notification_type, presence: true
	validate :metadata_is_hash

	scope :for_recipient, ->(pubkey) { where(recipient_pubkey: pubkey) }
	scope :recent, -> { order(created_at: :desc, id: :asc) }
	scope :unseen, -> { where(seen_at: nil) }
	scope :unread, -> { where(read_at: nil) }

	private

	def metadata_is_hash
		errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
	end
end
