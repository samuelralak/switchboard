# frozen_string_literal: true

# Shared plumbing for the Cashu system tests: injects the test-only cashu bridge (cashu-ts + the escrow
# module + scenarios) by resolving its hashed URL from the page import map, waits for it, runs a named escrow
# scenario in the browser, and probes the local mint. Kept out of the test classes so each stays small and
# they do not duplicate the loader. Not a *_test.rb file, so the runner never executes it as a test.
module CashuBridge
	MINT_URL = ENV["CASHU_MINT_URL"].presence || "http://127.0.0.1:3338"

	# Idempotently inject the bridge ES module + capture any in-page load/runtime error for diagnostics.
	INJECT_JS = <<~JS
	  if (!window.__cashuBridge) {
	    window.__cashuBridge = true
	    window.__cashuErr = null
	    window.addEventListener("error", (e) => { window.__cashuErr = String((e && e.message) || (e && e.error)) })
	    window.addEventListener("unhandledrejection", (e) => { window.__cashuErr = String(e.reason && (e.reason.message || e.reason)) })
	    const imports = JSON.parse(document.querySelector('script[type="importmap"]').textContent).imports
	    const s = document.createElement("script")
	    s.type = "module"
	    s.src = imports["nostr/cashu_test_support"]
	    s.addEventListener("error", () => { window.__cashuErr = "cashu bridge failed to load: " + s.src })
	    document.head.appendChild(s)
	  }
	JS

	RUN_SCENARIO_JS = <<~JS
	  const [name, mint] = arguments
	  const done = arguments[arguments.length - 1]
	  window.CashuEscrowTest.scenarios[name](mint)
	    .then((r) => done(JSON.stringify({ ok: true, value: r })))
	    .catch((e) => done(JSON.stringify({ ok: false, error: String((e && e.message) || e) })))
	JS

	RUN_SCENARIO_ARGS_JS = <<~JS
	  const [name, mint, argsJson] = arguments
	  const done = arguments[arguments.length - 1]
	  window.CashuEscrowTest.scenarios[name](mint, JSON.parse(argsJson))
	    .then((r) => done(JSON.stringify({ ok: true, value: r })))
	    .catch((e) => done(JSON.stringify({ ok: false, error: String((e && e.message) || e) })))
	JS

	def load_cashu_bridge(global = "CashuEscrowTest")
		execute_script(INJECT_JS)
		20.times do
			return if evaluate_script("typeof window.#{global}") == "object"

			sleep 0.5
		end
		flunk("cashu bridge did not load; in-page error: #{evaluate_script('window.__cashuErr')}")
	end

	# Run a named escrow scenario (defined in cashu_test_support.js) against the mint; returns its result Hash.
	def run_scenario(name)
		raw = evaluate_async_script(RUN_SCENARIO_JS, name, MINT_URL)
		parsed = JSON.parse(raw)
		flunk("scenario #{name} failed: #{parsed['error']}") unless parsed["ok"]

		parsed["value"]
	end

	# As run_scenario, but passes a Ruby Hash/Array to the scenario as its second argument (JSON round-tripped).
	# Lets a multi-step flow hand intermediate state JS -> Ruby -> JS (e.g. the server-arbiter-signing spike).
	def run_scenario_args(name, args)
		raw = evaluate_async_script(RUN_SCENARIO_ARGS_JS, name, MINT_URL, args.to_json)
		parsed = JSON.parse(raw)
		flunk("scenario #{name} failed: #{parsed['error']}") unless parsed["ok"]

		parsed["value"]
	end

	# nil when the mint answers /v1/info, else a short reason (so the test can skip cleanly with context).
	def mint_unavailable_reason
		require "net/http"
		uri = URI("#{MINT_URL}/v1/info")
		res = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 3) { |h| h.get(uri.path) }
		res.is_a?(Net::HTTPSuccess) ? nil : "HTTP #{res.code}"
	rescue StandardError => e
		"#{e.class}: #{e.message}"
	end
end
