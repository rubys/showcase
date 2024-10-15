import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="assign-judges"
export default class extends Controller {
  connect() {
    const token = document.querySelector('meta[name="csrf-token"]').content;

    let active_checkbox = this.element.querySelector("input[type=checkbox][name=active]");
    active_checkbox.addEventListener("click", (event) => {
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
        .then(response => response.json())
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

    let review_solos = this.element.querySelector("select[id=review_solos]");
    if (review_solos) {
      review_solos.addEventListener("change", (event) => {
        fetch(event.target.dataset.reviewSolosUrl, {
          method: "POST",
          headers: window.inject_region({
            "X-CSRF-Token": token,
            "Content-Type": "application/json"
          }),
          credentials: "same-origin",
          redirect: "follow",
          body: JSON.stringify({ review_solos: event.target.value })
        });
      });
    }

    let dancing_checkbox = this.element.querySelector("input[type=checkbox][name=dancing_judge]");
    if (dancing_checkbox) {
      dancing_checkbox.addEventListener("click", (event) => {
        event.preventDefault();

        fetch(dancing_checkbox.dataset.url, {
          method: "PATCH",
          headers: window.inject_region({
            "X-CSRF-Token": token,
            "Content-Type": "application/json",
            "Accept": "application/json"
          }),
          credentials: "same-origin",
          redirect: "follow",
          body: JSON.stringify({person: {exclude_id: event.target.checked ? event.target.value : ""}})
        })
          .then(response => response.json())
          .then(json => event.target.checked = json.exclude_id);
      });
    }
  }
}
