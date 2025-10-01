import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="auto-submit"
export default class extends Controller {
  connect() {
    this.boundSubmit = this.submit.bind(this);

    for (let input of this.element.querySelectorAll("input,select,textarea")) {
      input.addEventListener("change", this.boundSubmit);
    }
  }

  disconnect() {
    for (let input of this.element.querySelectorAll("input,select,textarea")) {
      input.removeEventListener("change", this.boundSubmit);
    }
  }

  submit() {
    this.element.requestSubmit();
  }
}
