# frozen_string_literal: true

module Shared
	module Lamp
		# A status dot whose status selects size, fill, and motion:
		#   :current  active step
		#   :done     completed step
		#   :settled  settled step
		#   :fault    failed step
		#   :future   upcoming step
		class LampComponent < ApplicationComponent
			STATUSES = {
				current: "h-2.5 w-2.5 rounded-full bg-lamp-live shadow-lamp animate-pulse motion-reduce:animate-none",
				done: "h-2 w-2 rounded-full bg-copper",
				settled: "h-2.5 w-2.5 rounded-full bg-lamp-settled",
				fault: "h-2.5 w-2.5 rounded-full bg-lamp-fault",
				future: "h-2 w-2 rounded-full border border-border-strong"
			}.freeze

			def initialize(status: :future)
				@status = STATUSES.key?(status.to_s.to_sym) ? status.to_s.to_sym : :future
			end

			def klass = STATUSES.fetch(@status)
		end
	end
end
