class Location < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :name, presence: true, uniqueness: true

  belongs_to :user, optional: true
  has_many :showcases, dependent: :destroy,
    class_name: 'Showcase', foreign_key: :location_id
end
