# frozen_string_literal: true

require "dry-types"

# Shared dry-types container used by service option declarations.
module Types
	include Dry.Types()

	# Canonical service-listing vocabularies: the single source for the studio form's select options and
	# the future consumer-request validation contract (brief §7.1 / §9). The listing READ path stays
	# tolerant on purpose (it keeps a foreign listing's unknown value rather than coercing it away), so
	# these constrain authoring + validation, not parsing.
	FulfillmentMode = String.enum("automated", "manual")
	# "attachment" = the buyer supplies a file with their request; at request time its value resolves
	# to a Blossom blob URL (the buyer uploads it then, mirroring how the provider uploads listing images).
	InputFieldType  = String.enum("text", "longtext", "number", "url", "attachment")
end
