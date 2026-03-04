import { Controller } from "@hotwired/stimulus";

const LAYOUTS = ["number", "stacked", "split", "columns"];

export default class extends Controller {
  static values = { initial: { type: String, default: "number" } };

  connect() {
    this.layout = localStorage.getItem("counterLayout") || this.initialValue;
    this.applyLayout();
    document.body.addEventListener("keydown", this.keydown);
  }

  disconnect() {
    document.body.removeEventListener("keydown", this.keydown);
  }

  keydown = (event) => {
    let index = LAYOUTS.indexOf(this.layout);
    if (event.key === "ArrowRight" || event.key === "ArrowDown") {
      this.layout = LAYOUTS[(index + 1) % LAYOUTS.length];
      this.applyLayout();
    } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
      this.layout = LAYOUTS[(index - 1 + LAYOUTS.length) % LAYOUTS.length];
      this.applyLayout();
    }
  };

  applyLayout() {
    this.element.dataset.layout = this.layout;
    localStorage.setItem("counterLayout", this.layout);
  }
}
