require "test_helper"

class AnswerTest < ActiveSupport::TestCase
  test "should belong to person" do
    answer = answers(:kathryn_meal)
    assert_equal people(:Kathryn), answer.person
  end

  test "should belong to question" do
    answer = answers(:kathryn_meal)
    assert_equal questions(:meal_choice), answer.question
  end

  test "should validate uniqueness of person and question combination" do
    # Try to create duplicate answer for same person and question
    duplicate_answer = Answer.new(
      person: people(:Kathryn),
      question: questions(:meal_choice),
      answer_value: "Beef"
    )

    assert_not duplicate_answer.valid?
    assert_includes duplicate_answer.errors[:person_id], "has already been taken"
  end

  test "should allow same question for different people" do
    answer = Answer.new(
      person: people(:Arthur),
      question: questions(:meal_choice),
      answer_value: "Beef"
    )

    assert answer.valid?
  end

  test "should allow different questions for same person" do
    # Create a new question first
    new_question = Question.create!(
      billable: billables(:two),
      question_text: "Another question",
      question_type: "textarea"
    )

    answer = Answer.new(
      person: people(:Kathryn),
      question: new_question,
      answer_value: "Gluten free"
    )

    assert answer.valid?, "Should allow same person to answer different questions"
  end

  test "should allow null answer_value" do
    answer = Answer.new(
      person: people(:Arthur),
      question: questions(:meal_choice),
      answer_value: nil
    )

    assert answer.valid?
  end

  test "should allow empty string answer_value" do
    answer = Answer.new(
      person: people(:Arthur),
      question: questions(:meal_choice),
      answer_value: ""
    )

    assert answer.valid?
  end

  test "should save radio button choice" do
    answer = Answer.create!(
      person: people(:Arthur),
      question: questions(:meal_choice),
      answer_value: "Vegetarian"
    )

    assert_equal "Vegetarian", answer.answer_value
  end

  test "should save textarea answer" do
    answer = Answer.create!(
      person: people(:Arthur),
      question: questions(:dietary_restrictions),
      answer_value: "No shellfish, lactose intolerant"
    )

    assert_equal "No shellfish, lactose intolerant", answer.answer_value
  end

  test "should update existing answer" do
    answer = answers(:kathryn_meal)
    assert_equal "Chicken", answer.answer_value

    answer.update!(answer_value: "Fish")
    assert_equal "Fish", answer.answer_value
  end

  test "should be destroyed when person is destroyed" do
    person = people(:Kathryn)
    answer_count = person.answers.count

    assert answer_count > 0, "Person should have answers"

    assert_difference 'Answer.count', -answer_count do
      person.destroy
    end
  end

  test "should be destroyed when question is destroyed" do
    question = questions(:meal_choice)
    answer_count = question.answers.count

    assert answer_count > 0, "Question should have answers"

    assert_difference 'Answer.count', -answer_count do
      question.destroy
    end
  end
end
