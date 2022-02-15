class Score < ApplicationRecord
  belongs_to :judge, nil, class_name: 'Person'
  belongs_to :heat
end
