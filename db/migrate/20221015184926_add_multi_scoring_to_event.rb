class AddMultiScoringToEvent < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :multi_scoring, :string, default: '1'
  end
end
