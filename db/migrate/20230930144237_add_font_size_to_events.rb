class AddFontSizeToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :font_size, :string, default: "100%"
  end
end
