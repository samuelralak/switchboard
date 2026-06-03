# frozen_string_literal: true

# A NullStore silently accepts every write, which would turn the NIP-98 replay guard
# (Sessions::ReplayGuard) and Rails' rate_limit into no-ops -- both fail OPEN against it.
# Refuse to boot with it outside the test environment, where it is the intended store.
Rails.application.config.after_initialize do
	if !Rails.env.test? && Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
		raise "Rails.cache is a NullStore: replay protection and rate_limit would silently no-op. Use a real store."
	end
end
