class CreatePackageIncludes < ActiveRecord::Migration[7.0]
  def change
    create_table :package_includes do |t|
      t.references :package, null: false, foreign_key: { to_table: :billables }
      t.references :option, null: false, foreign_key: { to_table: :billables }

      t.timestamps
    end
  end
end
