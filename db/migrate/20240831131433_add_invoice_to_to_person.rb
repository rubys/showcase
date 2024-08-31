class AddInvoiceToToPerson < ActiveRecord::Migration[7.1]
  def change
    add_reference :people, :invoice_to, foreign_key: { to_table: :people }
  end
end
