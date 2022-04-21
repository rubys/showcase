import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="formation"
export default class extends Controller {
  static targets = [ "primary", "partner", "instructor" ];

  connect() {
    this.boxes = [this.primaryTarget, this.partnerTarget].concat(this.instructorTargets);
    this.preventDupes();

    for (let box of this.boxes) {
      box.addEventListener('change', this.preventDupes)
    }
  }

  preventDupes = () => {
    let taken = [];
    for (let box of this.boxes) {
      for (let option of box.querySelectorAll('option')) {
        if (taken.includes(option.value)) {
          option.disabled = true;
          if (option.value == box.value) box.value = null;
        } else {
          option.disabled = false;
          if (!box.value) box.value = option.value;
        }
      }

      taken.push(box.value);
    }
  }
}
