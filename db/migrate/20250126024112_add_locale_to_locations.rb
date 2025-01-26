class AddLocaleToLocations < ActiveRecord::Migration[8.0]
  def change
    add_column :locations, :locale, :string, default: "en_US"
  end
end














