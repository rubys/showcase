class CreateCategories < ActiveRecord::Migration[7.0]
  def change
    create_table :categories do |t|
      t.string :name
      t.integer :order
      t.string :day
      t.string :time

      t.timestamps
    end

    remove_column :dances, :category, :string

    add_reference :dances, :open_category, foreign_key: {to_table: :categories}
    add_reference :dances, :closed_category, foreign_key: {to_table: :categories}
  end
end
