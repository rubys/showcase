class Event < ApplicationRecord
  validates :date, chronic: true, allow_blank: true
  has_one_attached :counter_art
end
