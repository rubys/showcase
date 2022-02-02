class Studio < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  has_many :people

  has_many :studio1_pairs, class_name: "StudioPair", foreign_key: :studio2_id
  has_many :studio1s, through: :studio1_pairs, source: :studio1

  has_many :studio2_pairs, class_name: "StudioPair", foreign_key: :studio1_id
  has_many :studio2s, through: :studio2_pairs, source: :studio2

  def pairs
    (studio1s + studio2s).uniq
  end
end
