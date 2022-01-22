class Person < ApplicationRecord
  self.inheritance_column = nil
  
  belongs_to :studio
end
