import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="auto-submit"
export default class extends Controller {
  connect() {
    for (let input of this.element.querySelectorAll("input,select")) {
      input.addEventListener("change", _event => {
        this.element.requestSubmit();
      });
    }
  }
}
