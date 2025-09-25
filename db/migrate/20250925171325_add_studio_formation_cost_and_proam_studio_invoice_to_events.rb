class AddStudioFormationCostAndProamStudioInvoiceToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :studio_formation_cost, :decimal, precision: 7, scale: 2
    add_column :events, :proam_studio_invoice, :string, default: "A"
  end
end
