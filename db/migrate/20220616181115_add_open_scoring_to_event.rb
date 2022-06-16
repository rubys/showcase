class AddOpenScoringToEvent < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :open_scoring, :string, default: '1'
  end
end
