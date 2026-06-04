# frozen_string_literal: true

module NostrClient
	# The outcome of publishing one EVENT to one relay: the relay's NIP-01 OK verdict, or a
	# local :timeout / :error when no usable OK arrived.
	#   status: :ok (relay accepted), :rejected (relay returned false, e.g. duplicate/blocked),
	#           :timeout (no OK within the window), :error (not connected / disconnected mid-flight)
	PublishResult = Data.define(:url, :status, :message) do
		def ok? = status == :ok
	end
end
