class AddProHeats < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :pro_heats, :boolean, default: false

    add_reference :dances, :pro_open_category, null: true, foreign_key: {to_table: :categories}
    add_reference :dances, :pro_closed_category, null: true, foreign_key: {to_table: :categories}
    add_reference :dances, :pro_solo_category, null: true, foreign_key: {to_table: :categories}
    add_reference :dances, :pro_multi_category, null: true, foreign_key: {to_table: :categories}

    add_column :categories, :pro, :boolean, default: false
  end
end
