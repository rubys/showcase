class AddDefaultPackageToStudios < ActiveRecord::Migration[7.0]
  def change
    add_reference :studios, :default_student_package, null: true, foreign_key: {to_table: :billables}
  end
end
