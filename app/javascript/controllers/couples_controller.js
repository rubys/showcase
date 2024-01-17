import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="couples"
export default class extends Controller {
  connect() {
    let billable_type = document.getElementById("billable_type")
    let billable_couples = document.getElementById("billable_couples")

    function couples_visibilty() {
      if (billable_type.value == "Student") {
        billable_couples.parentElement.classList.remove("hidden")
      } else {
        billable_couples.parentElement.classList.add("hidden")
        billable_couples.checked = false
      }
    }

    if (billable_type) {
      couples_visibilty()

      billable_type.addEventListener("change", couples_visibilty)
    }
  }
}
