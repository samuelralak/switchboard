# frozen_string_literal: true

module Orders
	# Visual preview of the URL-driven order drawer chrome (the lazy frame can't load without a session, so it
	# shows the "Loading order…" placeholder; this is just to check the slide-over panel + header).
	class DrawerPreview < ViewComponent::Preview
		def default; end
	end
end
