class Location < ApplicationRecord
  normalizes :key, with: -> name { name.strip }
  normalizes :name, with: -> name { name.strip }
  
  validates :key, presence: true, uniqueness: true
  validates :name, presence: true, uniqueness: true

  belongs_to :user, optional: true
  has_many :showcases, dependent: :destroy,
    class_name: 'Showcase', foreign_key: :location_id
end
