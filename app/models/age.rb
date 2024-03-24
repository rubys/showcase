class Age < ApplicationRecord
  has_one :costs, required: false, class_name: 'AgeCost', dependent: :destroy
end
