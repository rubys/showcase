class Clearwater < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :print_studio_heats, :boolean, default: false
    add_column :billables, :couples, :boolean, default: false
  end
end
