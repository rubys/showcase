class Dance < ApplicationRecord
  belongs_to :open_category, class_name: 'Category', optional: true
  belongs_to :closed_category, class_name: 'Category', optional: true

  has_many :heats, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :order, presence: true, uniqueness: true
end
