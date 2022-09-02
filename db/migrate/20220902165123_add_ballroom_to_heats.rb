class AddBallroomToHeats < ActiveRecord::Migration[7.0]
  def change
    add_column :heats, :ballroom, :string
  end
end
