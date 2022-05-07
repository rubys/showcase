class AddSlotToScore < ActiveRecord::Migration[7.0]
  def change
    add_column :scores, :slot, :integer
  end
end
