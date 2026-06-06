# frozen_string_literal: true

module Studio
	module ServiceForm
		# One image thumbnail in the studio picker: the preview, a cover badge, set-cover + remove controls,
		# an upload/error status overlay, and the hidden NIP-92 imeta inputs (url/m/x/dim) the form submits.
		# Rendered into a <template> the image-upload controller clones per file (and, later, server-side for
		# an existing listing image on edit). `image` is a { url:, m:, x:, dim: } hash; `cover` flags the first.
		class ImageItemComponent < ApplicationComponent
			def initialize(image: {}, cover: false)
				@image = (image || {}).symbolize_keys
				@cover = cover
			end

			attr_reader :image

			def cover? = @cover
			def uploaded? = image[:url].present?
			# error is a client-only state; a server-rendered item is either done (has a url) or absent.
			def errored? = false
			def state = uploaded? ? "done" : "uploading"
		end
	end
end
