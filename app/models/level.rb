class Level < ApplicationRecord
  def initials
    return '*' if id == 0
    name.gsub(/[^A-Z]/, '')
  end
end
