class AddSoloLengthToEvent < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :solo_length, :integer
  end
end
