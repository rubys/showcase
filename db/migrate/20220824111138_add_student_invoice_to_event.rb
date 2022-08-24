class AddStudentInvoiceToEvent < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :student_package_description, :string
    add_column :events, :payment_due, :string
  end
end
