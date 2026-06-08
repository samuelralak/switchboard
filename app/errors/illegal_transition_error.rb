# frozen_string_literal: true

# An order was asked to make a transition its state machine does not allow.
class IllegalTransitionError < ServiceError; end
