# frozen_string_literal: true

require "test_helper"

module Messages
	class BuildRumorTest < ActiveSupport::TestCase
		PUB  = "611df01bfcf85c26ae65453b772d8f1dfd25c264621c0277e1fc1518686faef9"
		RCPT = "166bf3765ebd1fc55decfe395beff2ea3b2a4e0a8946e7eb578512b555737c99"

		test "builds an unsigned kind-14 rumor with a self-consistent id and a p tag" do
			rumor = Messages::BuildRumor.call(author_pubkey: PUB, content: "hi", recipients: [ RCPT ])

			assert_not rumor.key?("sig")
			assert_equal Events::Kinds::DIRECT_MESSAGE, rumor["kind"]
			assert_equal PUB, rumor["pubkey"]
			assert_equal "hi", rumor["content"]
			assert_includes rumor["tags"], [ "p", RCPT ]
			assert_equal Events::Actions::ComputeCanonicalId.call(event: rumor), rumor["id"]
		end

		test "supports the kind-15 file message" do
			rumor = Messages::BuildRumor.call(author_pubkey: PUB, content: "f", kind: Events::Kinds::FILE_MESSAGE)
			assert_equal Events::Kinds::FILE_MESSAGE, rumor["kind"]
		end

		test "adds subject and reply (e) tags" do
			rumor = Messages::BuildRumor.call(author_pubkey: PUB, content: "re", subject: "Spec", reply_to: "a" * 64)
			assert_includes rumor["tags"], %w[subject Spec]
			assert_includes rumor["tags"], [ "e", "a" * 64 ]
		end
	end
end
