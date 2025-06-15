class Judge < ApplicationRecord
  belongs_to :person
  has_many :recordings, dependent: :destroy
end
