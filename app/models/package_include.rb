class PackageInclude < ApplicationRecord
  belongs_to :package, class_name: 'Billable'
  belongs_to :option, class_name: 'Billable'
end
