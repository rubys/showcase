class AddRegionToLocation < ActiveRecord::Migration[7.0]
  def change
    add_column :locations, :region, :string
  end
end
