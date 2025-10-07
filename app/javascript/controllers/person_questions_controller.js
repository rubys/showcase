import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="person-questions"
export default class extends Controller {
  static targets = ["questionsContainer", "optionCheckbox", "packageSelect"]
  static values = {
    personId: Number,
    url: String
  }

  connect() {
    // Don't update on initial load - let the server-rendered content show
    // Only update when package or options change
  }

  // Called when package dropdown changes
  packageChanged() {
    this.updateQuestions()
  }

  // Called when any option checkbox changes
  optionChanged() {
    this.updateQuestions()
  }

  updateQuestions() {
    // Get selected package
    const packageId = this.hasPackageSelectTarget ?
      this.packageSelectTarget.value : null

    // Get selected options (checkboxes that are checked and not disabled)
    const selectedOptions = []
    this.optionCheckboxTargets.forEach(checkbox => {
      if (checkbox.checked && !checkbox.disabled) {
        // Extract option ID from name like "person[options][123]"
        const match = checkbox.name.match(/\[options\]\[(\d+)\]/)
        if (match) {
          selectedOptions.push(match[1])
        }
      }
    })

    // Fetch questions for these selections
    this.fetchQuestions(packageId, selectedOptions)
  }

  fetchQuestions(packageId, optionIds) {
    const params = new URLSearchParams()
    if (packageId) params.append('package_id', packageId)
    optionIds.forEach(id => params.append('option_ids[]', id))
    params.append('person_id', this.personIdValue)

    fetch(`${this.urlValue}?${params.toString()}`, {
      headers: {
        'Accept': 'text/html',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => response.text())
    .then(html => {
      this.questionsContainerTarget.innerHTML = html
    })
    .catch(error => {
      console.error('Error fetching questions:', error)
    })
  }
}
