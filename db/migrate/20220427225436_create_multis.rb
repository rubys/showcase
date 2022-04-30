class CreateMultis < ActiveRecord::Migration[7.0]
  def change
    create_table :multis do |t|
      t.references :parent, null: false, foreign_key: { to_table: :dances }
      t.references :dance, null: false, foreign_key: true
      t.integer :slot

      t.timestamps
    end

    add_reference :dances, :multi_category, null: true, foreign_key: {to_table: :categories}
    add_column :dances, :heat_length, :integer
  end
end
