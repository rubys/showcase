import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="person"
export default class extends Controller {
  static targets = [ "level", "age", "role", "back" ];

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
      this.roleTarget.style.role = 'block';
    } else {
      this.levelTarget.style.display = 'none';
      this.ageTarget.style.display = 'none';

      if (event.target.value == 'Guest') {
        this.roleTarget.style.display = 'none';
      } else {
        this.roleTarget.style.display = 'block';
      }
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
