class AddIntermixToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :intermix, :boolean, default: true
  end
end
