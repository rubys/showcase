class CreateAgeCosts < ActiveRecord::Migration[7.1]
  def change
    create_table :age_costs do |t|
      t.references :age, null: false, foreign_key: true
      t.decimal :heat_cost, precision: 7, scale: 2
      t.decimal :solo_cost, precision: 7, scale: 2
      t.decimal :multi_cost, precision: 7, scale: 2

      t.timestamps
    end
  end
end
