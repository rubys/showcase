class Showcase < ApplicationRecord
  normalizes :name, with: -> name { name.strip }
  normalizes :key, with: -> name { name.strip }

  validates :year, presence: true
  validates :name, presence: true, uniqueness: { scope: %i[location_id year] }
  validates :key, presence: true, uniqueness: { scope: %i[location_id year] }

  belongs_to :location

  def start_date
    date&.split(' - ')&.first
  end

  def start_date=(value)
    if value.present?
      if date&.include?(' - ')
        self.date = "#{value} - #{date.split(' - ').last}"
      else
        self.date = value
      end
    end
  end

  def end_date
    date&.split(' - ')&.last
  end

  def end_date=(value)
    if value.present? && start_date.present?
      self.date = "#{start_date} - #{value}"
    end
  end

  def self.url
    "https://#{hostname}/showcase"
  end

  def self.hostname
    "smooth.fly.dev"
  end
end
