class Region < ApplicationRecord
  self.inheritance_column = nil

  validates :type, inclusion: { in: %{fly kamal} }
end
