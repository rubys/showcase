import { Controller } from "@hotwired/stimulus"
import { checkStartTime } from "helpers/start_time"

// Connects to data-controller="start-time"
//
// Shows how a typed start time will be saved ("1:30" → 1:30 PM) and stops the
// form from being submitted with something that looks like a time but isn't.
export default class extends Controller {
  static targets = ["input", "hint"]

  connect() {
    this.check()
  }

  check() {
    const { error, hint } = checkStartTime(this.inputTarget.value)
    this.inputTarget.setCustomValidity(error)
    this.hintTarget.textContent = hint
  }
}
