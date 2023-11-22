class Level < ApplicationRecord
  has_one :event, dependent: :nullify, class_name: 'Event', foreign_key: :solo_level_id
  
  def initials
    return '*' if id == 0
    name.gsub(/[^A-Z]/, '')
  end
end
