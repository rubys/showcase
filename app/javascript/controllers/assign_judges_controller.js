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
        headers: window.inject_region({
          "X-CSRF-Token": token,
          "Content-Type": "application/json"
        }),
        credentials: "same-origin",
        redirect: "follow"
      })
        .then (response => response.json())
        .then(json => event.target.checked = json.present);
    });

    let ballroom = this.element.querySelector("select[id=ballroom]");
    if (ballroom) {
      ballroom.addEventListener("change", (event) => {
        fetch(event.target.dataset.ballroomUrl, {
          method: "POST",
          headers: window.inject_region({
            "X-CSRF-Token": token,
            "Content-Type": "application/json"
          }),
          credentials: "same-origin",
          redirect: "follow",
          body: JSON.stringify({ ballroom: event.target.value })
        });
      });
    }
  }
}
