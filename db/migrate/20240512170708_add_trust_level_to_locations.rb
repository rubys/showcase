class AddTrustLevelToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :trust_level, :integer, default: 0
  end
end
