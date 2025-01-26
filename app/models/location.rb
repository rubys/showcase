class Location < ApplicationRecord
  normalizes :key, with: -> name { name.strip }
  normalizes :name, with: -> name { name.strip }
  normalizes :locale, with: -> locale { locale.strip }
  
  validates :key, presence: true, uniqueness: true
  validates :name, presence: true, uniqueness: true
  validates :locale, presence: true, format: { with: /\A[a-z]{2}_[A-Z]{2}\z/, message: "must be in format 'xx_XX'" }

  belongs_to :user, optional: true
  has_many :showcases, dependent: :destroy,
    class_name: 'Showcase', foreign_key: :location_id
end

















