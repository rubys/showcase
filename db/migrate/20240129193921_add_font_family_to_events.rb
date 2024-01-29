class AddFontFamilyToEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :font_family, :string, default: "Helvetica, Arial"
  end
end
