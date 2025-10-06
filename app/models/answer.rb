class Answer < ApplicationRecord
  belongs_to :person
  belongs_to :question

  validates :person_id, uniqueness: { scope: :question_id }
end
