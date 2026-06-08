# frozen_string_literal: true

# Turns the recoverable errors a browser action can raise (bad params, a failed contract, an illegal state
# transition, a uniqueness/lookup miss) into a flash alert + redirect_back, instead of a 500. Include in an
# HTML controller whose actions call services that raise these; override error_redirect_fallback to change
# where a request with no referer lands.
module RedirectsOnError
	extend ActiveSupport::Concern

	RECOVERABLE = [
		ActionController::ParameterMissing, ValidationError, IllegalTransitionError,
		ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, NotFoundError, ActiveRecord::RecordNotFound
	].freeze

	included do
		rescue_from(*RECOVERABLE, with: :redirect_with_error)
	end

	private

	def redirect_with_error(error)
		redirect_back_or_to error_redirect_fallback, alert: error.try(:flash_message) || error.message
	end

	def error_redirect_fallback = root_path
end
