class CreateBillables < ActiveRecord::Migration[7.0]
  def change
    create_table :billables do |t|
      t.string :type
      t.string :name
      t.decimal :price, precision: 7, scale: 2
      t.integer :order

      t.timestamps
    end

    add_column :events, :heat_cost, :decimal, precision: 7, scale: 2
    add_column :events, :solo_cost, :decimal, precision: 7, scale: 2
    add_column :events, :multi_cost, :decimal, precision: 7, scale: 2

    add_reference :people, :package, null: true, foreign_key: {to_table: :billables}
  end
end
