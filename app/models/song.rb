class Song < ApplicationRecord
  normalizes :title, with: -> name { name.strip }

  belongs_to :dance
  has_one_attached :song_file, dependent: false

  validates :title, presence: true, uniqueness: { scope: :dance_id }
  validates :order, presence: true, uniqueness: true

  after_save :upload_blobs, if: -> { song_file.attached? && song_file.blob.created_at > 1.minute.ago }

  def download_song_file
    download_blob(song_file.blob)
  end
end
