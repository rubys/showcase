class CreateJudges < ActiveRecord::Migration[7.0]
  def change
    create_table :judges do |t|
      t.references :person, null: false, foreign_key: true
      t.string :sort

      t.timestamps
    end
  end
end
