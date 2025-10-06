class Question < ApplicationRecord
  belongs_to :billable
  has_many :answers, dependent: :destroy

  # Rails 8.0 compatible ordering scope
  scope :ordered, -> { order(arel_table[:order]) }

  validates :question_text, presence: true
  validates :question_type, presence: true, inclusion: { in: %w[radio textarea] }
  validate :choices_present_for_radio
  validate :prevent_type_change_with_answers

  # Serialize choices as JSON
  serialize :choices, coder: JSON

  before_save :handle_choice_removal

  private

  def choices_present_for_radio
    if question_type == 'radio' && (choices.nil? || choices.empty?)
      errors.add(:choices, "must be present for radio questions")
    end
  end

  def prevent_type_change_with_answers
    if question_type_changed? && persisted? && answers.exists?
      errors.add(:question_type, "cannot be changed when answers exist")
    end
  end

  def handle_choice_removal
    return unless question_type == 'radio' && choices_changed? && persisted?

    old_choices = choices_was || []
    new_choices = choices || []
    removed_choices = old_choices - new_choices

    return if removed_choices.empty?

    # Nullify answers that match removed choices
    answers.where(answer_value: removed_choices).update_all(answer_value: nil)
  end
end
