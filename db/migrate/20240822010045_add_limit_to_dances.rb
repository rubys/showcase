class AddLimitToDances < ActiveRecord::Migration[7.1]
  def change
    add_column :dances, :limit, :integer, null: true
  end
end
