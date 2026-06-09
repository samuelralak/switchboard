# frozen_string_literal: true

require "test_helper"

module NostrClient
	# Boots a real EventMachine reactor, so each test stops it (and joins the thread) in an ensure to
	# avoid leaking a reactor across the process's other tests.
	class ReactorTest < ActiveSupport::TestCase
		test "start boots EM, is idempotent, and running? reflects it" do
			reactor = NostrClient::Reactor.instance

			reactor.start
			assert reactor.running?
			thread = reactor.instance_variable_get(:@thread)

			reactor.start # idempotent: no second thread
			assert_same thread, reactor.instance_variable_get(:@thread)
		ensure
			reactor.stop
		end

		test "reset clears the inherited state so a forked worker re-inits its own reactor" do
			reactor = NostrClient::Reactor.instance
			reactor.start
			thread = reactor.instance_variable_get(:@thread)

			reactor.reset

			assert_not reactor.running?
			assert_nil reactor.instance_variable_get(:@thread)
		ensure
			EM.stop_event_loop if EM.reactor_running?
			thread&.join(2)
		end

		test "a fresh start after reset re-attaches a working reactor that executes scheduled work" do
			reactor = NostrClient::Reactor.instance
			reactor.start
			first = reactor.instance_variable_get(:@thread)
			reactor.reset # post-fork contract: state cleared (no real fork here, so this process's EM is still up)

			reactor.start
			assert reactor.running?, "start re-boots/re-attaches after reset"
			ran = Thread::Queue.new
			reactor.schedule { ran.push(true) }
			20.times { break unless ran.empty?; sleep 0.05 }

			assert_not ran.empty?, "the reactor executes scheduled work after the re-start"
		ensure
			EM.stop_event_loop if EM.reactor_running?
			first&.join(2)
			reactor.reset # leave the process-shared singleton clean for other tests
		end
	end
end
