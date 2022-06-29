import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="category-override"
export default class extends Controller {
  static targets = [ "toggle", "form" ];

  connect() {
    this.toggleTarget.addEventListener('change', this.toggleForm);
    this.toggleForm();
  }

  toggleForm = () => {
    let display = this.toggleTarget.checked ? 'block' : 'none';
    for (let target of this.formTargets) {
      target.style.display = display;
    }
  }
}