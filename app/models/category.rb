class Category < ApplicationRecord
  has_many :open_dances, dependent: :nullify,
    class_name: 'Dance', foreign_key: :open_category_id
  has_many :closed_dances, dependent: :nullify,
    class_name: 'Dance', foreign_key: :closed_category_id
  has_many :solo_dances, dependent: :nullify,
    class_name: 'Dance', foreign_key: :solo_category_id
  has_many :multi_dances, dependent: :destroy,
    class_name: 'Dance', foreign_key: :multi_category_id

  validates :name, presence: true, uniqueness: true
  validates :order, presence: true, uniqueness: true
end
