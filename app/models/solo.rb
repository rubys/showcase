class Solo < ApplicationRecord
  belongs_to :heat
  belongs_to :combo_dance, class_name: 'Dance', optional: true
  has_many :formations, dependent: :destroy

  validates_associated :heat
  validates :order, uniqueness: true
end
