class AddSplitToCategories < ActiveRecord::Migration[8.0]
  def up
    add_column :categories, :split, :string

    Category.all.where.not(heats: nil).each do |category|
      category.update(split: category.heats.to_s)
    end

    remove_column :categories, :heats
  end

  def down
    add_column :categories, :heats, :integer

    Category.all.where.not(split: nil).each do |category|
      category.update(heats: category.split.first.to_i)
    end

    remove_column :categories, :split
  end
end
