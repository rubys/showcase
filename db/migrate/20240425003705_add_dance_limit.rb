class AddDanceLimit < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :dance_limit, :integer, null: true
  end
end
