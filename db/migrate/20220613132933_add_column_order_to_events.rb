class AddColumnOrderToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :column_order, :integer, default: 1
  end
end
