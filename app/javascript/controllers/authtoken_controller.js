import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="authtoken"
export default class extends Controller {
  // See https://stackoverflow.com/a/69699490/836177
  connect() {
    this.element.querySelector('input[name="authenticity_token"]').value =
      document.querySelector('meta[name="csrf-token"]').getAttribute('content');
  }
}
