import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="autoform"
export default class extends Controller {
  connect() {
    let inputs = this.element.querySelectorAll("input");

    for (const input of inputs) {
      input.addEventListener("change", () => {
        fetch(this.element.action, {
          method: this.element.method,
          body: new FormData(this.element)
        })
          .catch(console.error);
      });
    }

    let selects = this.element.querySelectorAll("select");

    for (const input of selects) {
      input.addEventListener("input", () => {
        fetch(this.element.action, {
          method: this.element.method,
          body: new FormData(this.element)
        })
          .catch(console.error);
      });
    }
  }
}
