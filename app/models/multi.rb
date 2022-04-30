class Multi < ApplicationRecord
  belongs_to :parent, class_name: 'Dance'
  belongs_to :dance
end
