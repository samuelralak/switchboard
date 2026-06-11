# frozen_string_literal: true

# Presentation for the notification bell: maps a notification's type to its human headline, icon, and the
# order it points at. The copy is recipient-framed (each type has one recipient role, except refunded/expired
# which read the same for both parties).
module NotificationsHelper
	HEADLINES = {
		"request_claimed" => "A provider claimed your request.",
		"order_funded" => "Your order was funded. Deliver the work.",
		"order_delivered" => "Your order was delivered. Review and release.",
		"order_release_authorized" => "The buyer authorized release. Redeem to get paid.",
		"order_released" => "Your order was released.",
		"order_refunded" => "Your order was refunded.",
		"order_expired" => "Your order expired."
	}.freeze

	ICONS = {
		"request_claimed" => "hgi-package",
		"order_funded" => "hgi-checkmark-circle-02",
		"order_delivered" => "hgi-sent",
		"order_release_authorized" => "hgi-square-lock-02",
		"order_released" => "hgi-checkmark-circle-02",
		"order_refunded" => "hgi-alert-02",
		"order_expired" => "hgi-alert-02"
	}.freeze

	def notification_headline(notification) = HEADLINES.fetch(notification.notification_type, "Order update.")
	def notification_icon(notification) = ICONS.fetch(notification.notification_type, "hgi-notification-02")

	# Where a notification points: the order opened IN the orders hub (orders_path, NOT the deprecated single
	# /orders/:id page), or the notifications feed when the order id is absent. The hub resolves the tab from
	# the order id (Orders::Ui::State.hub), so a notification recipient lands on the right Buying/Selling side.
	def notification_order_path(notification)
		order_id = notification.metadata["order_id"]
		order_id.present? ? orders_path(order_id:) : notifications_path
	end

	# Stimulus data wiring the per-row mark-as-read on click. Only UNREAD rows get it, so an already-read row
	# is a plain link that issues no request. notification_path is now the (freed) PATCH update route.
	def read_on_click_data(notification)
		return {} if notification.read_at

		{ controller: "notification", notification_url_value: notification_path(notification), action: "notification#open" }
	end
end
