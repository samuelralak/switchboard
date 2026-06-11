# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications, id: :uuid do |t|
      t.string :recipient_pubkey, null: false
      t.string :notification_type, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :seen_at
      t.datetime :read_at

      t.timestamps
    end

    # The bell lists a recipient's notifications newest-first; unseen drives the badge count.
    add_index :notifications, %i[recipient_pubkey created_at]
    add_index :notifications, %i[recipient_pubkey seen_at]
  end
end
