require "test_helper"

class QuestionTest < ActiveSupport::TestCase
  test "should belong to billable" do
    question = questions(:meal_choice)
    assert_equal billables(:two), question.billable
  end

  test "should have many answers with dependent destroy" do
    question = questions(:meal_choice)
    assert_includes question.answers, answers(:kathryn_meal)

    # Destroy question should destroy answers
    assert_difference 'Answer.count', -1 do
      question.destroy
    end
  end

  test "should validate presence of question_text" do
    question = Question.new(
      billable: billables(:two),
      question_type: 'radio',
      choices: ['A', 'B']
    )
    assert_not question.valid?
    assert_includes question.errors[:question_text], "can't be blank"
  end

  test "should validate presence of question_type" do
    question = Question.new(
      billable: billables(:two),
      question_text: 'Test question'
    )
    assert_not question.valid?
    assert_includes question.errors[:question_type], "can't be blank"
  end

  test "should validate question_type inclusion" do
    question = Question.new(
      billable: billables(:two),
      question_text: 'Test question',
      question_type: 'invalid_type'
    )
    assert_not question.valid?
    assert_includes question.errors[:question_type], "is not included in the list"
  end

  test "should accept radio type" do
    question = Question.new(
      billable: billables(:two),
      question_text: 'Test question',
      question_type: 'radio',
      choices: ['A', 'B']
    )
    assert question.valid?
  end

  test "should accept textarea type" do
    question = Question.new(
      billable: billables(:two),
      question_text: 'Test question',
      question_type: 'textarea'
    )
    assert question.valid?
  end

  test "should require choices for radio type" do
    question = Question.new(
      billable: billables(:two),
      question_text: 'Test question',
      question_type: 'radio'
    )
    assert_not question.valid?
    assert_includes question.errors[:choices], "must be present for radio questions"
  end

  test "should not require choices for textarea type" do
    question = Question.new(
      billable: billables(:two),
      question_text: 'Test question',
      question_type: 'textarea'
    )
    assert question.valid?
  end

  test "should serialize choices as JSON" do
    question = questions(:meal_choice)
    assert_kind_of Array, question.choices
    assert_equal ["Beef", "Chicken", "Fish", "Vegetarian"], question.choices
  end

  test "should order by order field using ordered scope" do
    q1 = Question.create!(
      billable: billables(:two),
      question_text: 'First',
      question_type: 'textarea',
      order: 3
    )
    q2 = Question.create!(
      billable: billables(:two),
      question_text: 'Second',
      question_type: 'textarea',
      order: 4
    )

    # Get only the questions we just created
    ordered = Question.where(id: [q1.id, q2.id]).ordered.to_a
    assert_equal q1, ordered.first
    assert_equal q2, ordered.last
  end

  test "should prevent type change when answers exist" do
    question = questions(:meal_choice)
    assert question.answers.any?, "Question should have answers"

    question.question_type = 'textarea'
    assert_not question.valid?
    assert_includes question.errors[:question_type], "cannot be changed when answers exist"
  end

  test "should allow type change when no answers exist" do
    question = Question.create!(
      billable: billables(:two),
      question_text: 'New question',
      question_type: 'radio',
      choices: ['A', 'B']
    )

    question.question_type = 'textarea'
    question.choices = nil
    assert question.valid?
  end

  test "should nullify answers when choice is removed" do
    question = questions(:meal_choice)
    answer = answers(:kathryn_meal)

    assert_equal "Chicken", answer.answer_value

    # Remove "Chicken" from choices
    question.choices = ["Beef", "Fish", "Vegetarian"]
    question.save!

    answer.reload
    assert_nil answer.answer_value
  end

  test "should not nullify answers when choice is not removed" do
    question = questions(:meal_choice)
    answer = answers(:kathryn_meal)

    assert_equal "Chicken", answer.answer_value

    # Keep "Chicken" in choices, just reorder
    question.choices = ["Chicken", "Beef", "Fish", "Vegetarian"]
    question.save!

    answer.reload
    assert_equal "Chicken", answer.answer_value
  end

  test "should handle editing question text without affecting answers" do
    question = questions(:meal_choice)
    answer = answers(:kathryn_meal)

    original_answer = answer.answer_value

    question.question_text = "What meal would you prefer?"
    question.save!

    answer.reload
    assert_equal original_answer, answer.answer_value
  end
end
