import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="drop"
export default class extends Controller {
  connect() {
    for (let child of this.element.children) {
      if (child.draggable) {
        child.addEventListener('dragstart', event => {
          event.dataTransfer.setData('application/drag-id', child.getAttribute('data-drag-id'));
          event.dataTransfer.effectAllowed = "move";
        });

        child.addEventListener('dragover', event => {
          event.preventDefault();
          return true;
        });

        child.addEventListener('dragenter', event => {
          event.preventDefault();
        });

        child.addEventListener('drop', event => {
          const token = document.querySelector('meta[name="csrf-token"]').content;

          let source = event.dataTransfer.getData("application/drag-id");
          let target = child.getAttribute("data-drag-id");

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
