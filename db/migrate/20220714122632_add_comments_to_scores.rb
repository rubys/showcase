class AddCommentsToScores < ActiveRecord::Migration[7.0]
  def change
    add_column :scores, :comments, :string
  end
end
