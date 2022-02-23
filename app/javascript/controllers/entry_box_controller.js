import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="entry-box"
export default class extends Controller {
  static targets = [ "primary", "partner", "instructor" ];

  connect() {
    this.reveal();
  }

  reveal() {
    this.instructorTarget.style.display = 'none';
    if (this.instructorTarget.querySelector(`option[value="${this.partnerTarget.value}"]`)) return;
    if (this.instructorTarget.querySelector(`option[value="${this.primaryTarget.value}"]`)) return;
    this.instructorTarget.style.display = 'block';
  }
}
