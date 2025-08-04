class Feedback < ApplicationRecord
  # Rails 8.0 compatible ordering scope
  scope :ordered, -> { order(arel_table[:order]) }
end
