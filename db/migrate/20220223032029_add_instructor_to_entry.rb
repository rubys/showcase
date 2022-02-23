class AddInstructorToEntry < ActiveRecord::Migration[7.0]
  def change
    add_reference :entries, :instructor, null: true, foreign_key: {to_table: :people}
  end
end
