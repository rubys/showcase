import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="drop"
export default class extends Controller {
  connect() {
    let dragable = [...this.element.querySelectorAll("*[data-drag-id]")];
    let targets = dragable.map (node => node.dataset.dragId);

    for (let child of dragable) {
      child.style.cursor = "grab";

      if (child.draggable) {
        child.addEventListener("dragstart", event => {
          event.dataTransfer.setData("application/drag-id", child.dataset.dragId);
          event.dataTransfer.effectAllowed = "move";
          child.style.opacity = 0.4;
          event.stopPropagation();
        });

        child.addEventListener("dragend", _event => {
          child.style.opacity = 1;
          child.style.cursor = "default";
          event.stopPropagation();
        });

        child.addEventListener("dragover", event => {
          event.dataTransfer.dropEffect = "move";
          event.stopPropagation();
          event.preventDefault();
          return true;
        });

        child.addEventListener("drop", event => {
          const token = document.querySelector('meta[name="csrf-token"]').content;

          let source = event.dataTransfer.getData("application/drag-id");
          let target = child.getAttribute("data-drag-id");

          if (!targets.includes(source)) return;

          fetch(this.element.getAttribute("data-drop-action"), {
            method: "POST",
            headers: window.inject_region({
              "X-CSRF-Token": token,
              "Content-Type": "application/json"
            }),
            credentials: "same-origin",
            redirect: "follow",
            body: JSON.stringify({source, target, id: this.element.id})
          }).then (response => response.text())
            .then(html => Turbo.renderStreamMessage(html));

          event.stopPropagation();
          event.preventDefault();
        });
      }
    }
  }
}
