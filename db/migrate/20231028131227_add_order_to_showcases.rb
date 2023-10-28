class AddOrderToShowcases < ActiveRecord::Migration[7.0]
  def change
    add_column :showcases, :order, :integer
  end
end
