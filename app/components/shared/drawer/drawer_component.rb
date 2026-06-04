# frozen_string_literal: true

module Shared
	module Drawer
		# A right-side slide-over panel (Tailwind Plus Elements el-dialog), opened by the native
		# command invoker -- a `command="show-modal" commandfor="<id>"` button anywhere on the
		# page, closed with `command="close"`. No Stimulus. Renders the chrome (canvas backdrop,
		# surface-2 panel, header with title and close); the page passes the body as the content
		# block. Mirrors the layout's mobile-sidebar slide-over, flipped to the right.
		class DrawerComponent < ApplicationComponent
			attr_reader :title, :dialog_id

			def initialize(title:, id: "drawer")
				@title = title
				@dialog_id = id
			end
		end
	end
end
