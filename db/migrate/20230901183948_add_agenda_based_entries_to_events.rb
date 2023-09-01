class AddAgendaBasedEntriesToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :agenda_based_entries, :boolean, default: false
  end
end
