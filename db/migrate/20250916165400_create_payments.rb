class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.references :person, null: false, foreign_key: true
      t.decimal :amount
      t.date :date
      t.text :comment

      t.timestamps
    end
  end
end
