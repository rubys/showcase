class AddLockToCategory < ActiveRecord::Migration[7.1]
  def change
    add_column :categories, :locked, :boolean
  end
end
