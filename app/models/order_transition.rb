# frozen_string_literal: true

# One row in an order's append-only statesman ledger. jsonb metadata, so no serialize mixin.
class OrderTransition < ApplicationRecord
	belongs_to :order, inverse_of: :order_transitions
end
