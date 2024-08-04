class AddBallroomToStudios < ActiveRecord::Migration[7.1]
  def change
    add_column :studios, :ballroom, :string
  end
end
