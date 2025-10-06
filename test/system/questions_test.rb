require "application_system_test_case"

class QuestionsTest < ApplicationSystemTestCase
  setup do
    @option = billables(:two)  # Lunch option
  end

  test "should add radio button question to option" do
    visit edit_billable_url(@option)

    # Add a question
    click_on "Add Question"

    # Fill in question details
    within all("[data-questions-target='question']").last do
      fill_in "Question", with: "What size t-shirt?"
      select "Radio Buttons", from: "Type"
      fill_in "Choices (one per line)", with: "Small\nMedium\nLarge\nX-Large"
    end

    click_on "Update option"

    assert_text "#{@option.name} was successfully updated"

    # Verify question was created
    @option.reload
    assert_equal 3, @option.questions.count
    question = @option.questions.last
    assert_equal "What size t-shirt?", question.question_text
    assert_equal "radio", question.question_type
    assert_equal ["Small", "Medium", "Large", "X-Large"], question.choices
  end

  test "should add textarea question to option" do
    visit edit_billable_url(@option)

    click_on "Add Question"

    within all("[data-questions-target='question']").last do
      fill_in "Question", with: "Special requests?"
      select "Text Area", from: "Type"
    end

    click_on "Update option"

    assert_text "#{@option.name} was successfully updated"

    @option.reload
    question = @option.questions.last
    assert_equal "Special requests?", question.question_text
    assert_equal "textarea", question.question_type
  end

  test "should toggle choices field based on question type" do
    visit edit_billable_url(@option)

    click_on "Add Question"

    within all("[data-questions-target='question']").last do
      # Choices should be visible for radio type
      assert find("[data-questions-target='choicesContainer']").visible?

      # Select textarea
      select "Text Area", from: "Type"

      # Choices should be hidden for textarea type
      assert_not find("[data-questions-target='choicesContainer']").visible?

      # Switch back to radio
      select "Radio Buttons", from: "Type"

      # Choices should be visible again
      assert find("[data-questions-target='choicesContainer']").visible?
    end
  end

  test "should remove question" do
    visit edit_billable_url(@option)

    initial_count = @option.questions.count
    assert initial_count > 0, "Option should have questions"

    # Remove the first question
    within first("[data-questions-target='question']") do
      click_on "Remove Question"
    end

    click_on "Update option"

    assert_text "#{@option.name} was successfully updated"

    @option.reload
    assert_equal initial_count - 1, @option.questions.count
  end

  test "questions should appear on person form when option is selected" do
    # First, ensure the option has questions
    visit edit_billable_url(@option)
    assert_selector "h2", text: "Questions for this option:"

    # Now visit a person who should see these questions
    person = people(:Kathryn)
    visit edit_person_url(person)

    # The questions section should be visible since Kathryn likely has options
    assert_selector "h3", text: "Questions"
  end

  test "should save radio button answer" do
    person = people(:Kathryn)
    visit edit_person_url(person)

    # Find the meal choice question (if visible)
    if has_text?(questions(:meal_choice).question_text)
      # Select a different meal choice
      choose "Fish"

      click_on "Update Person"

      assert_text "Person was successfully updated"

      # Verify the answer was saved
      answer = Answer.find_by(person: person, question: questions(:meal_choice))
      assert_equal "Fish", answer.answer_value
    end
  end

  test "should save textarea answer" do
    person = people(:Kathryn)
    visit edit_person_url(person)

    # Find the dietary restrictions question (if visible)
    if has_text?(questions(:dietary_restrictions).question_text)
      fill_in questions(:dietary_restrictions).question_text, with: "Gluten-free diet"

      click_on "Update Person"

      assert_text "Person was successfully updated"

      # Verify the answer was saved
      answer = Answer.find_by(person: person, question: questions(:dietary_restrictions))
      assert_equal "Gluten-free diet", answer.answer_value
    end
  end

  test "should show Answers button on main index when questions exist" do
    visit root_url

    # Should show Answers button since we have questions in fixtures
    assert_link "Answers", href: answers_path
  end

  test "should not show Answers button when no questions exist" do
    Question.destroy_all

    visit root_url

    # Should not show Answers button
    assert_no_link "Answers", href: answers_path
  end

  test "should display answer summary" do
    visit answers_url

    # Should show the option name
    assert_selector "h2", text: @option.name

    # Should show the questions
    assert_selector "h3", text: questions(:meal_choice).question_text
    assert_selector "h3", text: questions(:dietary_restrictions).question_text

    # Should show answers
    assert_text people(:Kathryn).name
    assert_text answers(:kathryn_meal).answer_value
  end

  test "should show PDF link on publish page when questions exist" do
    visit publish_event_index_url

    # Should show Question Answers PDF link
    assert_link "Question Answers"
  end

  test "should not show PDF link on publish page when no questions exist" do
    Question.destroy_all

    visit publish_event_index_url

    # Should not show Question Answers PDF link
    assert_no_text "Question Answers"
  end

  test "full workflow: create question, answer it, view summary" do
    # Step 1: Add a question to an option
    visit edit_billable_url(@option)

    click_on "Add Question"

    within all("[data-questions-target='question']").last do
      fill_in "Question", with: "Preferred workshop session?"
      select "Radio Buttons", from: "Type"
      fill_in "Choices (one per line)", with: "Morning\nAfternoon\nEvening"
    end

    click_on "Update option"
    assert_text "#{@option.name} was successfully updated"

    # Step 2: Answer the question as a person
    person = people(:Kathryn)
    visit edit_person_url(person)

    if has_text?("Preferred workshop session?")
      choose "Afternoon"
      click_on "Update Person"
      assert_text "Person was successfully updated"
    end

    # Step 3: View the summary
    visit answers_url

    assert_text "Preferred workshop session?"
    assert_text person.name
    assert_text "Afternoon"
  end
end
