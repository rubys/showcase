class AddSoloCategoryToDance < ActiveRecord::Migration[7.0]
  def change
    add_reference :dances, :solo_category, null: true, foreign_key: {to_table: :categories}

    reversible do |dir|
      dir.up do
        Dance.all.each do |dance|
          dance.update_columns(solo_category_id: dance.closed_category_id)
        end
      end
    end
  end
end
