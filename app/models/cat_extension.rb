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

  def cost_override
    category.cost_override
  end

  def pro
    category.pro
  end
end
