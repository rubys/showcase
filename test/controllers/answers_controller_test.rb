require "test_helper"

class AnswersControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get answers_url
    assert_response :success
  end

  test "index should show options with questions" do
    get answers_url
    assert_response :success
    assert_select 'h2', text: billables(:two).name
  end

  test "index should show questions and answers" do
    get answers_url
    assert_response :success

    # Should show the question
    assert_select 'h3', text: questions(:meal_choice).question_text

    # Should show the person's name
    assert_select 'td', text: people(:Kathryn).name

    # Should show the answer
    assert_select 'td', text: answers(:kathryn_meal).answer_value
  end

  test "index should show message when no questions exist" do
    # Delete all questions
    Question.destroy_all

    get answers_url
    assert_response :success
    assert_select 'p', text: /No questions have been defined yet/
  end

  test "index should show link to PDF report when questions exist" do
    get answers_url
    assert_response :success
    assert_select 'a[href=?]', report_answers_path(format: :pdf), text: /Download PDF Report/
  end

  test "should get report as HTML" do
    get report_answers_url
    assert_response :success
  end

  test "report should show options with questions" do
    get report_answers_url
    assert_response :success
    assert_select 'h2', text: billables(:two).name
  end

  test "report should show questions and answers" do
    get report_answers_url
    assert_response :success

    # Should show the question
    assert_select 'h3', text: questions(:meal_choice).question_text

    # Should show the person's name
    assert_select 'td', text: people(:Kathryn).name

    # Should show the answer
    assert_select 'td', text: answers(:kathryn_meal).answer_value
  end

  test "should handle empty answers gracefully" do
    # Create a question with no answers
    q = Question.create!(
      billable: billables(:two),
      question_text: "New question",
      question_type: "textarea"
    )

    get answers_url
    assert_response :success
    assert_select 'p', text: /No answers yet for this question/
  end

  test "should show 'No answer provided' for null answers" do
    # Create an answer with null value
    Answer.create!(
      person: people(:Arthur),
      question: questions(:meal_choice),
      answer_value: nil
    )

    get answers_url
    assert_response :success
    assert_select 'span.text-gray-400', text: /No answer provided/
  end

  test "should group answers by option and question" do
    get answers_url
    assert_response :success

    # The meal_choice and dietary_restrictions questions should both appear
    # under the Lunch option
    assert_select 'h2', text: 'Lunch' do
      assert_select '~ div h3', text: questions(:meal_choice).question_text
      assert_select '~ div h3', text: questions(:dietary_restrictions).question_text
    end
  end
end
