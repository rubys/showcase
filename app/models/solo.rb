class Solo < ApplicationRecord
  belongs_to :heat
  belongs_to :combo_dance, class_name: 'Dance', optional: true
  validates_associated :heat

  validates :order, uniqueness: true
end
