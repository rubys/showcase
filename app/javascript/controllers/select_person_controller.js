import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="select-person"
export default class extends Controller {
  static targets = ["studio"];

  connect() {
    this.token = document.querySelector('meta[name="csrf-token"]').content; 

    this.studioTarget.addEventListener("change", _event => {
      if (this.studioTarget.value == "") {
        let select_person = document.getElementById("select-person");
        while (select_person.firstChild) {
          select_person.lastChild.remove();
        }
      } else {
        fetch(this.studioTarget.getAttribute("data-url"), {
          method: "POST",
          headers: window.inject_region({
            "X-CSRF-Token": this.token,
            "Content-Type": "application/json"
          }),
          credentials: "same-origin",
          redirect: "follow",
          body: JSON.stringify({studio_id: this.studioTarget.value})
        }).then (response => response.text())
          .then(html => Turbo.renderStreamMessage(html));
      }
    });
  }
}
