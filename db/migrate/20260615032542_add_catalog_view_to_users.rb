# frozen_string_literal: true

# A logged-in viewer's saved catalog view (all | verified), or NULL to follow the operator default. Local
# preference, preserved across kind-0 re-projection like `flagged` (Users::Profilable never touches it).
class AddCatalogViewToUsers < ActiveRecord::Migration[8.1]
	def change
		add_column :users, :catalog_view, :string
	end
end
