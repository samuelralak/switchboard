# frozen_string_literal: true

require "uri"
require "ipaddr"

module Shared
	# Canonicalize a relay URL, or return nil if it is unusable OR unsafe to dial. A user's NIP-65 r-tags
	# become OUTBOUND socket targets from the relay:boot ingest, so this is the anti-SSRF gate: only ws/wss,
	# no embedded credentials, and no loopback/private/link-local IPs or localhost/.local/.onion hosts.
	# Canonical form (lowercase scheme+host, default port + trailing slashes stripped) is the dedup key, so
	# the browser and server agree on one URL per relay. Returns nil to drop a bad/hostile entry; callers
	# map+compact, so a junk r-tag is filtered rather than raising.
	class NormalizeRelayUrl < BaseService
		MAX_LENGTH = 200
		DEFAULT_PORTS = { "ws" => 80, "wss" => 443 }.freeze

		option :url

		def call
			raw = url.to_s.strip
			return if raw.empty? || raw.length > MAX_LENGTH

			uri = parse(raw) or return
			return unless safe_host?(uri.host)

			canonical(uri)
		end

		private

		def parse(raw)
			uri = URI.parse(raw)
			return unless %w[ws wss].include?(uri.scheme&.downcase)
			return if uri.userinfo.present? # no embedded credentials
			return if uri.host.blank?

			uri
		rescue URI::InvalidURIError
			nil
		end

		def canonical(uri)
			scheme = uri.scheme.downcase
			host = uri.host.downcase
			port = uri.port && uri.port != DEFAULT_PORTS[scheme] ? ":#{uri.port}" : ""
			path = uri.path.to_s.sub(%r{/+\z}, "") # strip one-or-more trailing slashes

			"#{scheme}://#{host}#{port}#{path}"
		end

		# Reject hosts that point at our own infra or private networks. An IP literal is range-checked; a
		# hostname must be a public FQDN (a bare/no-dot name, .local, or .onion is treated as internal).
		def safe_host?(host)
			down = host.downcase
			return false if down == "localhost" || down.end_with?(".local", ".onion")
			return false unless down.include?(".")

			literal = ip_literal(down)
			literal ? public_ip?(literal) : true
		end

		def ip_literal(host)
			IPAddr.new(host.delete("[]")) # tolerate a bracketed IPv6 literal
		rescue IPAddr::InvalidAddressError
			nil
		end

		def public_ip?(ip)
			return false if ip.loopback? || ip.private? || ip.link_local?
			return false if ip.ipv4? && IPAddr.new("0.0.0.0/8").include?(ip) # "this network"

			true
		end
	end
end
