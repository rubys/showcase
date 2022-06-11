class AddTrackAgesToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :track_ages, :boolean, default: true
  end
end
