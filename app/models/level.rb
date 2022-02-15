class Level < ApplicationRecord
  def initials
    name.gsub(/[^A-Z]/, '')
  end
end
