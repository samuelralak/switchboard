# frozen_string_literal: true

# The absolute origin the sign-in `u` tag is verified against (never request.url/Host,
# which a reverse proxy could spoof). The client signs exactly this origin + /session.
Rails.application.config.x.canonical_origin = ENV.fetch("CANONICAL_ORIGIN", "http://localhost:3000")
