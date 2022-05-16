class Billable < ApplicationRecord
  self.inheritance_column = nil

  validates :name, presence: true, uniqueness: { scope: :type }
  validates :price, presence: true

  has_many :person_options
  has_many :package_includes, dependent: :destroy, class_name: 'PackageInclude', foreign_key: :package_id
  has_many :option_included_by, dependent: :destroy, class_name: 'PackageInclude', foreign_key: :option_id
  has_many :default_student_package_for, dependent: :nullify, class_name: 'Studio', foreign_key: :default_student_package_id
  has_many :people, class_name: 'Person', foreign_key: :package_id
end
