# frozen_string_literal: true

# The in-app notification feed. `index` is the full history page; `seen` marks the recipient's unseen
# notifications seen (clearing the bell badge), called when the dropdown opens. Beyond the seen-marker this is
# read-only -- the rows are a projection written by Notifications::Deliver, never authored here.
class NotificationsController < ApplicationController
	before_action :require_login

	# The recent feed (latest 100). A fuller history with pagination is a follow-up; 100 covers the active
	# window for a new feature, and the bell itself shows only the latest dozen.
	def index
		@notifications = Notification.for_recipient(current_user.pubkey).recent.limit(100)
	end

	# Mark one notification read (the recipient opened it). Scoped to the signed-in user via the relation, so an
	# id that is not theirs updates zero rows and 204s -- no record lookup, no existence leak, no IDOR.
	def update
		scope = Notification.for_recipient(current_user.pubkey).where(id: params[:id])
		# Bulk UPDATE on the single scoped row; idempotent, no per-row callbacks/validations (cf. #seen).
		scope.update_all(read_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
		broadcast_read_row(scope.first)
		head :no_content
	end

	# Mark every unseen notification for the signed-in user as seen. Idempotent; no body (the bell clears its
	# badge optimistically). Broadcasts the cleared badge so the user's OTHER open tabs/devices clear too.
	def seen
		# One bulk UPDATE for a seen-marker; no per-row callbacks/validations are wanted (cf. LoginChallenge).
		Notification.for_recipient(current_user.pubkey).unseen.update_all(seen_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
		broadcast_cleared_badge
		head :no_content
	end

	private

	# Best-effort: a broadcast failure must not fail the seen-marker (which already committed).
	def broadcast_cleared_badge
		Notifications::Ui::Update.refresh_badge(pubkey: current_user.pubkey)
	rescue StandardError => e
		Rails.error.report(e, handled: true, context: { pubkey: current_user.pubkey })
	end

	# Best-effort: push the now-read row so the unread dot clears on the user's other open tabs/devices. Nil
	# when the id was not the user's (the no-op IDOR path) -- nothing to broadcast.
	def broadcast_read_row(notification)
		return unless notification

		Notifications::Ui::Update.refresh_row(notification:)
	rescue StandardError => e
		Rails.error.report(e, handled: true, context: { notification_id: notification&.id })
	end
end
