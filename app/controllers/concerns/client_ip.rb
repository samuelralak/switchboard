# frozen_string_literal: true

# The trustworthy client IP for rate limiting. Behind the Fly proxy the client-supplied X-Forwarded-For is
# appendable (so request.remote_ip is spoofable), so prefer Fly's authoritative Fly-Client-IP header, falling
# back to remote_ip off Fly (dev/test/other hosts).
module ClientIp
	extend ActiveSupport::Concern

	private

	def client_ip = request.headers["Fly-Client-IP"].presence || request.remote_ip
end
