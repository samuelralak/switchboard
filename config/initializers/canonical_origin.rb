# frozen_string_literal: true

# The absolute origin the sign-in `u` tag is verified against (never request.url/Host, which a reverse proxy
# could spoof). The client signs exactly this origin + /session. In production it MUST be provisioned: a
# localhost default would silently defeat NIP-98 origin pinning and break sign-in. The SECRET_KEY_BASE_DUMMY
# guard skips the check during asset precompile, where the value is neither needed nor necessarily present.
canonical_origin = ENV["CANONICAL_ORIGIN"].presence

if canonical_origin.nil? && Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
	raise "CANONICAL_ORIGIN must be set in production (the NIP-98 sign-in origin); a localhost default breaks auth"
end

Rails.application.config.x.canonical_origin = canonical_origin || "http://localhost:3000"
