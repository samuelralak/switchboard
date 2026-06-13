# frozen_string_literal: true

require "test_helper"

module Profiles
	module Ui
		# Unit-tests the Portfolio value object's role-scoping invariant directly (fakes, no DB): the section
		# body, the heading count pill, and the reputation-strip count all read one role-scoped collection, so
		# they never disagree and a visitor never sees the owner's drafts. The factory's DB wiring and
		# Profiles::Resolve's raise/lazy-fetch are covered by ProfilesControllerTest.
		class StateTest < ActiveSupport::TestCase
			Portfolio = State::Portfolio
			FakeListing = Struct.new(:active) { def active? = active }
			FakeRequest = Struct.new(:open) { def open? = open }
			PUBKEY = "a" * 64

			def portfolio(owner:, listings: [], requests: [], user: Object.new)
				Portfolio.new(pubkey: PUBKEY, user:, owner:, listings:, requests:)
			end

			test "the owner sees every listing and request (active + inactive), counted in full" do
				p = portfolio(owner: true,
					listings: [ FakeListing.new(true), FakeListing.new(false) ],
					requests: [ FakeRequest.new(true), FakeRequest.new(false), FakeRequest.new(true) ])

				assert_equal 2, p.services_shown.size
				assert_equal 2, p.service_count
				assert_equal 3, p.requests_shown.size
				assert_equal 3, p.request_count
			end

			test "a visitor sees only live items, and the counts hide the owner's drafts" do
				p = portfolio(owner: false,
					listings: [ FakeListing.new(true), FakeListing.new(false) ], # 1 active, 1 draft
					requests: [ FakeRequest.new(true), FakeRequest.new(false) ]) # 1 open, 1 withdrawn

				assert_equal 1, p.service_count
				assert p.services_shown.all?(&:active?)
				assert_equal 1, p.request_count
				assert p.requests_shown.all?(&:open?)
			end

			test "empty? is role-scoped: an owner's drafts are presence, a visitor's are not" do
				drafts_only = { listings: [ FakeListing.new(false) ], requests: [ FakeRequest.new(false) ] }

				assert_not portfolio(owner: true, **drafts_only).empty? # the owner still has rows to manage
				assert portfolio(owner: false, **drafts_only).empty?    # a visitor sees nothing live -> unified empty
			end

			test "projected? reflects a present user; npub encodes the pubkey" do
				assert portfolio(owner: false, user: Object.new).projected?
				assert_not portfolio(owner: false, user: nil).projected?
				assert_equal Nostr::Bech32.npub_encode(PUBKEY), portfolio(owner: false).npub
			end
		end
	end
end
