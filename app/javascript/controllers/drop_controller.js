import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="drop"
export default class extends Controller {
  connect() {
    let targets = [...this.element.querySelectorAll(':scope > *[data-drag-id]')].map (node => node.dataset.dragId);

    for (let child of this.element.children) {
      if (child.draggable) {
        child.addEventListener('dragstart', event => {
          event.dataTransfer.setData('application/drag-id', child.dataset.dragId);
          event.dataTransfer.effectAllowed = "move";
          child.style.opacity = 0.4;
        });

        child.addEventListener('dragend', event => {
          child.style.opacity = 1;
        });

        child.addEventListener('dragover', event => {
          let source = event.dataTransfer.getData("application/drag-id");
          if (targets.includes(source)) {
            event.preventDefault();
            event.dataTransfer.dropEffect = "move";
            return true;
          }
          return false;
        });

        child.addEventListener('dragenter', event => {
          let source = event.dataTransfer.getData("application/drag-id");
          if (targets.includes(source)) event.preventDefault();
        });

        child.addEventListener('drop', event => {
          const token = document.querySelector('meta[name="csrf-token"]').content;

          let source = event.dataTransfer.getData("application/drag-id");
          let target = child.getAttribute("data-drag-id");

          if (!targets.includes(source)) return;

          fetch(this.element.getAttribute('data-drop-action'), {
            method: 'POST',
            headers: {
              'X-CSRF-Token': token,
              'Content-Type': 'application/json'
            },
            credentials: 'same-origin',
            redirect: 'follow',
            body: JSON.stringify({source, target})
          }).then (response => response.text())
          .then(html => Turbo.renderStreamMessage(html));

          event.preventDefault()
        });
      }
    }
  }
}
