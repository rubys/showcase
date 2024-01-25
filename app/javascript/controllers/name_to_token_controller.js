import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="name-to-token"
export default class extends Controller {
  static targets = ["name", "token"]

  connect() {
    if (!this.nameTarget || !this.tokenTarget) return

    this.nameTarget.addEventListener("input", () => {
      if (this.normalize(this.nameTarget.getAttribute("value")) == (this.tokenTarget.getAttribute("value") || '')) {
        this.tokenTarget.value = this.normalize(this.nameTarget.value)
        this.tokenTarget.setAttribute("value", this.tokenTarget.value)
      }

      this.nameTarget.setAttribute("value", this.nameTarget.value)
    })

    this.tokenTarget.addEventListener("input", () => {
      this.tokenTarget.setAttribute("value", this.tokenTarget.value)
    })
  }

  normalize(name) {
    return (name || '').toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  }
}
