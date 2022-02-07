import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="person"
export default class extends Controller {
  static targets = [ "level", "age", "back" ];

  connect() {
    for (let select of [...document.querySelectorAll('select')]) {
      let changeEvent = new Event('change');
      select.dispatchEvent(changeEvent);
    }
  }

  setType(event) {
    if (event.target.value == 'Student') {
      this.levelTarget.style.display = 'block';
      this.ageTarget.style.display = 'block';
    } else {
      this.levelTarget.style.display = 'none';
      this.ageTarget.style.display = 'none';
    }
  }

  setRole(event) {
    if (event.target.value == 'Follower') {
      this.backTarget.style.display = 'none';
    } else {
      this.backTarget.style.display = 'block';
    }
  }
}
