class StudioPair < ApplicationRecord
  belongs_to :studio1, class_name: 'Studio'
  belongs_to :studio2, class_name: 'Studio'
end
