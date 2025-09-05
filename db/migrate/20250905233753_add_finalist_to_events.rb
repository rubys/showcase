class AddFinalistToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :finalist, :string, default: "F"
  end
end
