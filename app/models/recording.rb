class Recording < ApplicationRecord
  belongs_to :judge
  belongs_to :heat
  has_one_attached :audio

  after_save :upload_blobs, if: -> { audio.attached? && audio.blob.created_at > 1.minute.ago }
end
