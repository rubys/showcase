class AnswersController < ApplicationController
  include Printable

  # GET /answers
  def index
    load_answer_data
  end

  # GET /answers/report.pdf
  def report
    load_answer_data

    respond_to do |format|
      format.html
      format.pdf { render_as_pdf basename: "question-answers" }
    end
  end

  private

  def load_answer_data
    @event = Event.current

    # Get all options that have questions
    @options_with_questions = Billable.where(type: 'Option')
                                      .joins(:questions)
                                      .distinct
                                      .ordered

    # Build a structured data hash: option => question => [answers]
    @answer_data = {}

    @options_with_questions.each do |option|
      @answer_data[option] = {}

      option.questions.ordered.each do |question|
        # Get all answers for this question, with person and studio data
        answers = Answer.where(question_id: question.id)
                       .joins(:person)
                       .includes(person: :studio)
                       .order('people.name')

        @answer_data[option][question] = answers
      end
    end
  end
end
