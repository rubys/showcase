class CreateRecordings < ActiveRecord::Migration[8.0]
  def change
    create_table :recordings do |t|
      t.references :judge, null: false, foreign_key: true
      t.references :heat, null: false, foreign_key: true

      t.timestamps
    end

    add_column :events, :judge_recordings, :boolean, default: false
  end
end
