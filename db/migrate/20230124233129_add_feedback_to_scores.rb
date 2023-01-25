class AddFeedbackToScores < ActiveRecord::Migration[7.0]
  def change
    add_column :scores, :good, :string
    add_column :scores, :bad, :string
  end
end
