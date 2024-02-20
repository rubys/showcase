import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="person"
export default class extends Controller {
  static targets = [ "studio", "independent", "level", "age", "role", "back", "exclude", "type", "package", "options" ];

  connect() {
    this.id = JSON.parse(this.element.dataset.id);
    this.token = document.querySelector('meta[name="csrf-token"]')?.content;

    for (let select of [...document.querySelectorAll("select")]) {
      let changeEvent = new Event("change");
      select.dispatchEvent(changeEvent);
    }
  }

  setType(event) {
    if (event.target.value == "Student") {
      this.levelTarget.style.display = "block";
      if (this.hasAgeTarget) this.ageTarget.style.display = "block";
      this.roleTarget.style.display = "block";
      this.excludeTarget.style.display = "block";
      if (this.hasIndependentTarget) this.independentTarget.style.display = "none";
    } else {
      this.levelTarget.style.display = "none";
      if (this.hasAgeTarget) this.ageTarget.style.display = "none";

      if (event.target.value == "Professional") {
        this.roleTarget.style.display = "block";
        this.excludeTarget.style.display = "block";
        if (this.hasIndependentTarget) this.independentTarget.style.display = "block";
      } else {
        this.roleTarget.style.display = "none";
        this.backTarget.style.display = "none";
        this.excludeTarget.style.display = "none";
        if (this.hasIndependentTarget) this.independentTarget.style.display = "none";
      }
    }

    fetch(event.target.getAttribute("data-url"), {
      method: "POST",
      headers: window.inject_region({
        "X-CSRF-Token": this.token,
        "Content-Type": "application/json"
      }),
      credentials: "same-origin",
      redirect: "follow",
      body: JSON.stringify({id: this.id, type: event.target.value, studio_id: this.studioTarget.value})
    }).then (response => response.text())
      .then(html => Turbo.renderStreamMessage(html));
  }

  setRole(event) {
    if (event.target.value == "Follower") {
      this.backTarget.style.display = "none";
    } else {
      this.backTarget.style.display = "block";
    }
  }

  setPackage(event) {
    fetch(event.target.getAttribute("data-url"), {
      method: "POST",
      headers: window.inject_region({
        "X-CSRF-Token": this.token,
        "Content-Type": "application/json"
      }),
      credentials: "same-origin",
      redirect: "follow",
      body: JSON.stringify({id: this.id, type: this.typeTarget.value, package_id: event.target.value})
    }).then (response => response.text())
      .then(html => Turbo.renderStreamMessage(html));
  }
}
