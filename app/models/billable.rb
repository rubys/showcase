class Billable < ApplicationRecord
  self.inheritance_column = nil

  normalizes :name, with: -> name { name.strip }

  validates :name, presence: true, uniqueness: { scope: :type }
  validates :price, presence: true

  has_many :package_includes, dependent: :destroy, class_name: 'PackageInclude', foreign_key: :package_id
  has_many :option_included_by, dependent: :destroy, class_name: 'PackageInclude', foreign_key: :option_id
  has_many :default_student_package_for, dependent: :nullify, class_name: 'Studio', foreign_key: :default_student_package_id
  has_many :default_professional_package_for, dependent: :nullify, class_name: 'Studio', foreign_key: :default_professional_package_id
  has_many :default_guest_package_for, dependent: :nullify, class_name: 'Studio', foreign_key: :default_guest_package_id
  has_many :people_package, class_name: 'Person', dependent: :nullify, foreign_key: :package_id
  has_many :people_options, class_name: 'PersonOption', dependent: :destroy, foreign_key: :option_id

  def people
    if type == 'Option'
      people_options
    else
      people_package
    end
  end
end
