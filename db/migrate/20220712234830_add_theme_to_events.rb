class AddThemeToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :theme, :string
  end
end
