class AddSongToSolos < ActiveRecord::Migration[7.0]
  def change
    add_column :solos, :song, :string
    add_column :solos, :artist, :string
  end
end
