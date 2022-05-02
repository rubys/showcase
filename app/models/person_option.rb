class PersonOption < ApplicationRecord
  belongs_to :person
  belongs_to :option, class_name: 'Billable'
end
