class CatExtension < ApplicationRecord
  belongs_to :category

  def name
    "#{category.name} - Part #{part}"
  end

  def ballrooms
    category.ballrooms
  end

  def duration
    nil
  end
end
