import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="studio-price-override"
export default class extends Controller {
  connect() {
    this.checkbox = this.element.querySelector("input[type=checkbox]");
    this.checkbox.addEventListener("change", this.hideShow);
    this.hideShow();
  }

  hideShow = () => {
    for (let input of this.element.querySelectorAll("input[type=number]")) {
      input.parentElement.style.display = this.checkbox.checked ? "block" : "none";
      input.disabled = !this.checkbox.checked;
    }
  };
}
