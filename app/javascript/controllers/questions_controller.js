import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="questions"
export default class extends Controller {
  static targets = ["question", "choicesContainer", "destroyField"]

  connect() {
    this.questionIndex = this.questionTargets.length
  }

  addQuestion(event) {
    event.preventDefault()

    const container = document.getElementById("questions-container")
    const timestamp = new Date().getTime()

    const newQuestionHTML = `
      <div class="question-fields border border-gray-300 p-4 rounded-md" data-questions-target="question">
        <input type="hidden" name="billable[questions_attributes][${timestamp}][id]" value="">

        <div class="flex gap-4 items-start">
          <div class="flex-1">
            <label for="billable_questions_attributes_${timestamp}_question_text">Question</label>
            <textarea name="billable[questions_attributes][${timestamp}][question_text]"
                      id="billable_questions_attributes_${timestamp}_question_text"
                      rows="2"
                      class="block shadow rounded-md border border-gray-200 outline-none px-3 py-2 mt-2 w-full"></textarea>
          </div>

          <div class="w-48">
            <label for="billable_questions_attributes_${timestamp}_question_type">Type</label>
            <select name="billable[questions_attributes][${timestamp}][question_type]"
                    id="billable_questions_attributes_${timestamp}_question_type"
                    class="block shadow rounded-md border border-gray-200 outline-none px-3 py-2 mt-2 w-full"
                    data-action="change->questions#toggleChoices">
              <option value="radio">Radio Buttons</option>
              <option value="textarea">Text Area</option>
            </select>
          </div>
        </div>

        <div class="choices-container mt-3" data-questions-target="choicesContainer">
          <label for="billable_questions_attributes_${timestamp}_choices">Choices (one per line)</label>
          <textarea name="billable[questions_attributes][${timestamp}][choices]"
                    id="billable_questions_attributes_${timestamp}_choices"
                    rows="3"
                    placeholder="Beef&#10;Chicken&#10;Fish&#10;Vegetarian"
                    class="block shadow rounded-md border border-gray-200 outline-none px-3 py-2 mt-2 w-full"></textarea>
        </div>

        <input type="hidden" name="billable[questions_attributes][${timestamp}][order]" value="${this.questionIndex}">

        <div class="mt-3">
          <a href="#" class="text-red-600 hover:text-red-800" data-action="click->questions#removeQuestion">Remove Question</a>
        </div>
      </div>
    `

    container.insertAdjacentHTML('beforeend', newQuestionHTML)
    this.questionIndex++
  }

  removeQuestion(event) {
    event.preventDefault()
    const link = event.target.closest('a')
    const questionDiv = link.closest('[data-questions-target="question"]')
    const questionName = link.dataset.questionName

    if (questionName) {
      // Question already exists in database, create _destroy field and mark for destruction
      const destroyField = document.createElement('input')
      destroyField.type = 'hidden'
      destroyField.name = `${questionName}[_destroy]`
      destroyField.value = '1'
      questionDiv.appendChild(destroyField)
      questionDiv.style.display = "none"
    } else {
      // New question, just remove from DOM
      questionDiv.remove()
    }
  }

  toggleChoices(event) {
    const select = event.target
    const questionDiv = select.closest('[data-questions-target="question"]')
    const choicesContainer = questionDiv.querySelector('[data-questions-target="choicesContainer"]')

    if (select.value === 'textarea') {
      choicesContainer.style.display = 'none'
    } else {
      choicesContainer.style.display = 'block'
    }
  }
}
