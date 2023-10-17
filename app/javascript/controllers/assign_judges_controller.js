import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="assign-judges"
export default class extends Controller {
  connect() {
    const token = document.querySelector('meta[name="csrf-token"]').content;

    let checkbox = this.element.querySelector("input[type=checkbox][name=active]");
    checkbox.addEventListener("click", (event) => {
      event.preventDefault();

      fetch(this.element.dataset.presentUrl, {
        method: "POST",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json"
        },
        credentials: "same-origin",
        redirect: "follow"
      })
        .then (response => response.json())
        .then(json => event.target.checked = json.present);
    });
  }
}
