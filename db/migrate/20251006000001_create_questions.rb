class CreateQuestions < ActiveRecord::Migration[8.0]
  def change
    create_table :questions do |t|
      t.references :billable, null: false, foreign_key: true
      t.text :question_text, null: false
      t.string :question_type, null: false
      t.text :choices
      t.integer :order

      t.timestamps
    end

    add_index :questions, [:billable_id, :order]
  end
end
