class AddClosedScoringToEvent < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :closed_scoring, :string, default: 'G'
  end
end
