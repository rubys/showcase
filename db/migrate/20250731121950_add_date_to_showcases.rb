class AddDateToShowcases < ActiveRecord::Migration[8.0]
  def change
    add_column :showcases, :date, :string
  end
end
