class AddProAmToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :pro_am, :string, default: "G"
    add_column :events, :solo_scoring, :string, default: "1"
  end
end
