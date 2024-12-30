class CreateRegions < ActiveRecord::Migration[8.0]
  def change
    create_table :regions do |t|
      t.string :type
      t.string :code
      t.string :location
      t.float :latitude
      t.float :longitude

      t.timestamps
    end
  end
end
