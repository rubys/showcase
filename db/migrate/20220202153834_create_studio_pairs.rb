class CreateStudioPairs < ActiveRecord::Migration[7.0]
  def change
    create_table :studio_pairs do |t|
      t.references :studio1, null: false, foreign_key: { to_table: :studios }
      t.references :studio2, null: false, foreign_key: { to_table: :studios }

      t.timestamps
    end
  end
end
