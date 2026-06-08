# frozen_string_literal: true

module Messages
	module ServiceDetail
		# The service detail shown in the right slide-over when a provider clicks the service in a thread.
		# Delegates to the SAME canonical detail the catalogue/requests pages use (Catalog::ServiceDetail for
		# a listing, Requests::RequestDetail for an open request), with the buyer/claim CTA suppressed, so the
		# drawer is identical everywhere. `service` is the resolved Catalog::Listing / Requests::OpenRequest
		# (nil when the event is not ingested locally).
		class ServiceDetailComponent < ApplicationComponent
			# The dialog id the thread's trigger button and the drawer share (one service shows at a time).
			DRAWER_ID = "service-drawer"

			attr_reader :service, :viewer

			def initialize(service:, viewer: nil)
				@service = service
				@viewer = viewer
			end

			def listing? = service.is_a?(Catalog::Listing)
			def request? = service.is_a?(Requests::OpenRequest)
		end
	end
end
