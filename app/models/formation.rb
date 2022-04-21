# While the formation controller represents a solo with multiple
# participants, a formation model represents a single participant.

class Formation < ApplicationRecord
  belongs_to :person
  belongs_to :solo
end
