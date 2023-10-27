class Location < ApplicationRecord
  belongs_to :user, optional: true
  has_many :showcases, dependent: :destroy,
    class_name: 'Showcase', foreign_key: :location_id
end
