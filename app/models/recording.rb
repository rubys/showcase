class Recording < ApplicationRecord
  belongs_to :judge
  belongs_to :heat
  has_one_attached :audio
end
