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

    // Set up radio button deselection behavior using event delegation
    this.element.addEventListener('click', this.handleRadioClick.bind(this))

    // Track initial state of radio buttons
    this.markCheckedRadios()
  }

  // Called when package dropdown changes
  packageChanged() {
    this.updateQuestions()
  }

  // Called when any option checkbox changes
  optionChanged() {
    this.updateQuestions()
  }

  // Handle radio button clicks to allow deselection
  handleRadioClick(event) {
    const radio = event.target.closest('input[type="radio"]')
    if (!radio) return

    // If this radio is already checked, uncheck it
    if (radio.checked && radio.dataset.wasChecked === 'true') {
      radio.checked = false
      delete radio.dataset.wasChecked
    } else {
      // Clear wasChecked from all radios in this group
      const name = radio.name
      this.element.querySelectorAll(`input[type="radio"][name="${name}"]`).forEach(r => {
        delete r.dataset.wasChecked
      })
      // Mark this one as checked
      if (radio.checked) {
        radio.dataset.wasChecked = 'true'
      }
    }
  }

  // Mark currently checked radio buttons
  markCheckedRadios() {
    this.element.querySelectorAll('input[type="radio"]:checked').forEach(radio => {
      radio.dataset.wasChecked = 'true'
    })
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
      // Mark checked state for dynamically loaded radio buttons
      this.markCheckedRadios()
    })
    .catch(error => {
      console.error('Error fetching questions:', error)
    })
  }
}
