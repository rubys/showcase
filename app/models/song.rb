class Song < ApplicationRecord
  normalizes :title, with: -> name { name.strip }

  belongs_to :dance
  has_one_attached :song_file, dependent: false

  validates :title, presence: true, uniqueness: { scope: :dance_id }
  validates :order, presence: true, uniqueness: true
end
