class AddGridToDances < ActiveRecord::Migration[7.0]
  def change
    add_column :dances, :row, :integer
    add_column :dances, :col, :integer
  end
end
