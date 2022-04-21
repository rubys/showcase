class AddBallroomsToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :ballrooms, :integer, default: 1
  end
end
