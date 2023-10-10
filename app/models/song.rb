class Song < ApplicationRecord
  belongs_to :dance
  has_one_attached :song_file

  validates :title, presence: true, uniqueness: { scope: :dance_id }
  validates :order, presence: true, uniqueness: true
end
