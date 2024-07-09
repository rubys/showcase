class AddCounterColorToEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :counter_color, :string, default: '#FFFFFF'
  end
end
