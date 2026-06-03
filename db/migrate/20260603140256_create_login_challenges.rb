# frozen_string_literal: true

class CreateLoginChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :login_challenges, id: :uuid do |t|
      t.string   :nonce, null: false        # 64-hex single-use sign-in nonce (SecureRandom.hex(32))
      t.datetime :expires_at, null: false    # short TTL; the client must sign within the window
      t.datetime :consumed_at                # nil until claimed; the single-use gate

      t.timestamps
    end

    add_index :login_challenges, :nonce, unique: true
    add_index :login_challenges, :expires_at # supports sweeping expired rows
  end
end
