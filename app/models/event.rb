class Event < ApplicationRecord
  validates :date, chronic: true, allow_blank: true
end
