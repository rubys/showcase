class AddMoreDefaultPackagesToStudios < ActiveRecord::Migration[7.0]
  def change
    add_reference :studios, :default_professional_package, null: true, foreign_key: {to_table: :billables}
    add_reference :studios, :default_guest_package, null: true, foreign_key: {to_table: :billables}
    add_column :events, :package_required, :boolean, default: true
  end
end
