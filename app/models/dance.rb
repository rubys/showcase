class Dance < ApplicationRecord
  belongs_to :open_category, class_name: 'Category', optional: true
  belongs_to :closed_category, class_name: 'Category', optional: true
  belongs_to :solo_category, class_name: 'Category', optional: true
  belongs_to :multi_category, class_name: 'Category', optional: true

  belongs_to :pro_open_category, class_name: 'Category', optional: true
  belongs_to :pro_closed_category, class_name: 'Category', optional: true
  belongs_to :pro_solo_category, class_name: 'Category', optional: true
  belongs_to :pro_multi_category, class_name: 'Category', optional: true

  has_many :heats, dependent: :destroy
  has_many :songs, dependent: :destroy
  has_many :multi_children, dependent: :destroy, class_name: 'Multi', foreign_key: :parent_id
  has_many :multi_dances, dependent: :destroy, class_name: 'Multi', foreign_key: :dance_id

  validates :name, presence: true, uniqueness: true
  validates :order, presence: true, uniqueness: true
end
