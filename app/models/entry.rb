class Entry < ApplicationRecord
  belongs_to :dance
  belongs_to :lead, class_name: 'Person'
  belongs_to :follow, class_name: 'Person'
end
