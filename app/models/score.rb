class Score < ApplicationRecord
  belongs_to :judge, nil, class_name: 'Person'
  belongs_to :heat
  # validates_associated :heat # Too dangerous to validate during scoring
end
