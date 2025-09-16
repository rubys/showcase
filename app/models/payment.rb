class Payment < ApplicationRecord
  belongs_to :person

  validates :amount, presence: true, numericality: true
  validates :date, presence: true
end
