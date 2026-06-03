# frozen_string_literal: true

class AddReplaceableCoordinateIndexToEvents < ActiveRecord::Migration[8.1]
  def change
    # NIP-01 replaceable kinds (0, 3, 10000..19999) keep one row per (pubkey, kind);
    # this enforces it so a concurrent cold insert raises and Upsert retries to supersede.
    add_index :events, [ :pubkey, :kind ], unique: true,
      where: "kind = 0 OR kind = 3 OR (kind >= 10000 AND kind < 20000)",
      name: "index_events_on_replaceable_coordinate"
  end
end
