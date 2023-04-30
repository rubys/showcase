class AddJudgeCommentsToEvent < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :judge_comments, :boolean, default: false
  end
end
