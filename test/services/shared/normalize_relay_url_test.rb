# frozen_string_literal: true

require "test_helper"

module Shared
	class NormalizeRelayUrlTest < ActiveSupport::TestCase
		def normalize(url) = Shared::NormalizeRelayUrl.call(url:)

		test "lowercases scheme and host and trims whitespace" do
			assert_equal "wss://relay.example.com", normalize("  WSS://Relay.Example.COM  ")
		end

		test "strips trailing slashes (one or many) but preserves a real path" do
			assert_equal "wss://relay.example.com", normalize("wss://relay.example.com/")
			assert_equal "wss://relay.example.com", normalize("wss://relay.example.com///")
			assert_equal "wss://relay.example.com/path", normalize("wss://relay.example.com/path/")
		end

		test "strips the default port but keeps a non-default one" do
			assert_equal "wss://relay.example.com", normalize("wss://relay.example.com:443")
			assert_equal "ws://relay.example.com", normalize("ws://relay.example.com:80")
			assert_equal "wss://relay.example.com:8080", normalize("wss://relay.example.com:8080")
		end

		test "accepts ws and wss only" do
			assert_nil normalize("https://relay.example.com")
			assert_nil normalize("http://relay.example.com")
			assert_equal "ws://relay.example.com", normalize("ws://relay.example.com")
		end

		test "rejects blank, nil, and over-long urls" do
			assert_nil normalize("")
			assert_nil normalize("   ")
			assert_nil normalize(nil)
			assert_nil normalize("wss://#{'a' * 300}.example.com")
		end

		test "rejects embedded credentials (anti-SSRF)" do
			assert_nil normalize("wss://user:pass@relay.example.com")
		end

		test "rejects loopback, localhost, and bare hostnames" do
			assert_nil normalize("wss://localhost")
			assert_nil normalize("wss://127.0.0.1")
			assert_nil normalize("ws://[::1]")
			assert_nil normalize("wss://internal-relay") # no dot: internal-looking
		end

		test "rejects private, link-local, and cloud-metadata addresses" do
			assert_nil normalize("wss://10.0.0.5")
			assert_nil normalize("wss://192.168.1.10")
			assert_nil normalize("wss://172.16.4.4")
			assert_nil normalize("wss://169.254.169.254") # cloud metadata (link-local)
			assert_nil normalize("wss://0.0.0.0")
		end

		test "rejects .local and .onion hosts" do
			assert_nil normalize("wss://relay.local")
			assert_nil normalize("wss://abcdefg.onion")
		end

		test "accepts a public FQDN and a public IP literal" do
			assert_equal "wss://relay.damus.io", normalize("wss://relay.damus.io")
			assert_equal "wss://1.2.3.4", normalize("wss://1.2.3.4")
		end
	end
end
