class AddPartnerlessEntriesToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :partnerless_entries, :boolean, default: false
  end
end
