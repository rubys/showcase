class AddOrderToDances < ActiveRecord::Migration[7.0]
  def change
    add_column :dances, :order, :integer

    reversible do |dir|
      dir.up do
        Dance.all.each do |dance|
          dance.update_columns(order: dance.id)
        end
      end
    end
  end
end
