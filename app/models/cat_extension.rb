class CatExtension < ApplicationRecord
  belongs_to :category

  def name
    "#{category.name} - Part #{part}"
  end
end
