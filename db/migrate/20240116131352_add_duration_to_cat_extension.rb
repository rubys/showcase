class AddDurationToCatExtension < ActiveRecord::Migration[7.1]
  def change
    add_column :cat_extensions, :duration, :integer
  end
end
