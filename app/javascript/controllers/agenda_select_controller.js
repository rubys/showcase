import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="agenda-select"
export default class extends Controller {
  connect() {
    this.token = document.querySelector('meta[name="csrf-token"]')?.content;

    let select = this.element.querySelector("select");

    select.addEventListener("change", event => {
      fetch(this.element.dataset.url, {
        method: "POST",
        headers: window.inject_region({
          "X-CSRF-Token": this.token,
          "Content-Type": "application/json"
        }),
        credentials: "same-origin",
        redirect: "follow",
        body: JSON.stringify({
          id: event.target.value,
          solo: this.element.dataset.solo == "true"
        })
      }).then (response => response.text())
        .then(html => Turbo.renderStreamMessage(html));
    })
  }
}
