class CreateSongs < ActiveRecord::Migration[7.0]
  def change
    create_table :songs do |t|
      t.references :dance, null: false, foreign_key: true
      t.integer :order
      t.string :title
      t.string :artist

      t.timestamps
    end
  end
end
