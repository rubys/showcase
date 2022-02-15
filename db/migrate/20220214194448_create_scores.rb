class CreateScores < ActiveRecord::Migration[7.0]
  def change
    create_table :scores do |t|
      t.references :judge, null: false, foreign_key: {to_table: :people}
      t.references :heat, null: false, foreign_key: true
      t.string :value

      t.timestamps
    end
  end
end
