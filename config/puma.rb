# frozen_string_literal: true

# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1. You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Worker processes (clustered mode) when WEB_CONCURRENCY is set; default 0 keeps the single-process,
# threads-only server. Relay publish sockets live on a per-process EventMachine reactor, so clustering
# is what makes the fork hooks below matter.
worker_count = ENV.fetch("WEB_CONCURRENCY", 0).to_i
workers worker_count

# Load the app in the master before forking so the fork hooks below see NostrClient/Operational loaded
# (otherwise before_worker_boot's defined?() guard would silently skip booting the per-worker publish
# sockets, and the first clustered web publish would then hit the fail-loud raise). Clustered mode only.
preload_app! if worker_count.positive?

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# Relay publish sockets live on a background EventMachine reactor. The process that SERVES requests must hold
# them so a server-side publish (the attestation label) reaches relays instead of hitting the fail-loud raise.
# Only a provisioned R_op key with configured DM relays opens connections, so dev/test stay socket-free either
# way. The reactor does NOT survive fork, so clustered mode boots per-worker; single mode boots once on boot.
if worker_count.positive?
	before_fork do
		NostrClient.stop if defined?(NostrClient)
	rescue StandardError => e
		warn "[NostrClient] before_fork stop skipped: #{e.class}: #{e.message}"
	end

	before_worker_boot do
		next unless defined?(NostrClient) && defined?(Operational::Signer)

		NostrClient.reactor.reset
		NostrClient.boot_publishing! if Operational::Signer.configured? && NostrClient.configuration.relays.any?
	rescue StandardError => e
		warn "[NostrClient] before_worker_boot publishing skipped: #{e.class}: #{e.message}"
	end
else
	# Single-process server: no worker fork fires, so this one serving process opens the sockets itself once
	# Puma has booted. Without this the web process holds no connections and a server-side publish is lost.
	on_booted do
		next unless defined?(NostrClient) && defined?(Operational::Signer)

		NostrClient.boot_publishing! if Operational::Signer.configured? && NostrClient.configuration.relays.any?
	rescue StandardError => e
		warn "[NostrClient] on_booted publishing skipped: #{e.class}: #{e.message}"
	end
end
