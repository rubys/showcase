class CreatePersonOptions < ActiveRecord::Migration[7.0]
  def change
    create_table :person_options do |t|
      t.references :person, null: false, foreign_key: true
      t.references :option, null: false, foreign_key: { to_table: :billables }

      t.timestamps
    end
  end
end
