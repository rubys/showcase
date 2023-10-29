class Showcase < ApplicationRecord
  validates :year, presence: true
  validates :name, presence: true, uniqueness: { scope: %i[location_id year] }
  validates :key, presence: true, uniqueness: { scope: %i[location_id year] }

  belongs_to :location
end
