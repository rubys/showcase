class Dance < ApplicationRecord
  has_many :dances, dependent: :destroy
end
