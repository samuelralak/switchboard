# frozen_string_literal: true

# A revocable login session (Rails 8 auth pattern): the signed cookie holds only this row's
# id, so a session can be terminated server-side by destroying the row. Sessions also expire
# after an absolute lifetime (MAX_AGE) -- resume_session ignores older rows and the recurring
# reaper deletes them, so a leaked cookie cannot grant access indefinitely.
class Session < ApplicationRecord
	MAX_AGE = 30.days

	belongs_to :user

	scope :active, -> { where(created_at: MAX_AGE.ago..) }
end
