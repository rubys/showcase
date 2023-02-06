import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="entry-box"
export default class extends Controller {
  static targets = [ "primary", "partner", "instructor", "role" ];

  connect() {
    this.reveal();
  }

  reveal() {
    if (this.hasRoleTarget) {
      let boths = JSON.parse(this.roleTarget.dataset.boths);
      if (boths.includes(parseInt(this.partnerTarget.value))) {
        this.roleTarget.style.display = 'block';
      } else {
        this.roleTarget.style.display = 'none';
      }
    }

    this.instructorTarget.style.display = 'none';
    if (this.instructorTarget.querySelector(`option[value="${this.partnerTarget.value}"]`)) return;
    if (this.instructorTarget.querySelector(`option[value="${this.primaryTarget.value}"]`)) return;
    this.instructorTarget.style.display = 'block';
  }
}