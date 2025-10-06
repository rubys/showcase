class CreateAnswers < ActiveRecord::Migration[8.0]
  def change
    create_table :answers do |t|
      t.references :person, null: false, foreign_key: true
      t.references :question, null: false, foreign_key: true
      t.text :answer_value

      t.timestamps
    end

    add_index :answers, [:person_id, :question_id], unique: true
  end
end
