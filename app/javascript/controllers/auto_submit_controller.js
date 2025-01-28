import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="auto-submit"
export default class extends Controller {
  connect() {
    for (let input of this.element.querySelectorAll("input,select")) {
      console.log(input);
      input.addEventListener("change", _event => {
        console.log(this.element);
        this.element.requestSubmit();
      });
    }
  }
}
