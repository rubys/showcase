class AddTableSizeToBillables < ActiveRecord::Migration[8.0]
  def change
    add_column :billables, :table_size, :integer
  end
end
