class AllowHeatNumberToBeAFloat < ActiveRecord::Migration[7.0]
  def up
    change_column :heats, :number, :float
  end

  def down
    change_column :heats, :number, :integer
  end
end
