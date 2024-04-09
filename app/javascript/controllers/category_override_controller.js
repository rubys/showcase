import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="category-override"
export default class extends Controller {
  static targets = [ "toggle", "form" ];

  connect() {
    this.toggleTarget.addEventListener("change", this.toggleForm);
    this.toggleForm();

    let category_routines = document.getElementById("category_routines");
    if (category_routines) {
      this.toggleIncludes(category_routines.checked);

      category_routines.addEventListener("click", () => {
        this.toggleIncludes(category_routines.checked);
      });
    }
  }

  toggleForm = () => {
    let display = this.toggleTarget.checked ? "block" : "none";
    for (let target of this.formTargets) {
      target.style.display = display;
    }
  };

  toggleIncludes = routine => {
    for (let checkbox of document.querySelectorAll("input[type=checkbox]")) {
      if (checkbox.id.startsWith("category[include]")) {
        checkbox.disabled = routine;
        checkbox.parentElement.parentElement.parentElement.style.display =
          (routine ? "none" : "block");
      }
    }
  };
}