class AddHeatsToCategory < ActiveRecord::Migration[7.0]
  def change
    add_column :categories, :heats, :integer
  end
end
