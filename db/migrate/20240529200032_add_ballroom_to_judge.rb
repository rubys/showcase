class AddBallroomToJudge < ActiveRecord::Migration[7.1]
  def change
    add_column :judges, :ballroom, :string, null: false, default: 'Both'
  end
end
