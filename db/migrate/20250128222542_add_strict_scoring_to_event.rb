class AddStrictScoringToEvent < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :strict_scoring, :boolean, default: false
  end
end
