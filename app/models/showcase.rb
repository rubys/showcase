class Showcase < ApplicationRecord
  normalizes :name, with: -> name { name.strip }
  normalizes :key, with: -> name { name.strip }

  validates :year, presence: true
  validates :name, presence: true, uniqueness: { scope: %i[location_id year] }
  validates :key, presence: true, uniqueness: { scope: %i[location_id year] }

  belongs_to :location

  def self.url
    "https://smooth.fly.dev/showcase"
  end

  def self.hostname
    "smooth.fly.dev"
  end
end
