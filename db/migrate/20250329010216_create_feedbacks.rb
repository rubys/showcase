class CreateFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :feedbacks do |t|
      t.integer :order
      t.string :value
      t.string :abbr

      t.timestamps
    end
  end
end
