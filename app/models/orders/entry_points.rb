# frozen_string_literal: true

module Orders
	# How an order was opened.
	module EntryPoints
		CATALOG_ORDER = "catalog_order"
		REQUEST_CLAIM = "request_claim"

		ALL = [ CATALOG_ORDER, REQUEST_CLAIM ].freeze
	end
end
