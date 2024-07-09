class AddPrevNumberToHeats < ActiveRecord::Migration[7.1]
  def up
    add_column :heats, :prev_number, :float
    Heat.update_all 'prev_number = number'
  end

  def down
    remove_column :heats, :prev_number
  end
end
