import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="score"
export default class extends Controller {
  keydown(event) {
    if (event.key == 'ArrowRight') {
      let link = document.querySelector('a[rel=next]')
      if (link) link.click();
    } else if (event.key == 'ArrowLeft') {
      let link = document.querySelector('a[rel=prev]')
      if (link) link.click();
    }
  }

  disconnect() {
    document.body.addRemoveListener('keydown', this.keydown);
  }

  connect() {
    document.body.addEventListener('keydown', this.keydown);

    for (let subject of this.element.querySelectorAll('*[draggable=true]')) {
      subject.addEventListener('dragstart', event => {
        event.dataTransfer.setData('application/drag-id', subject.id);
        event.dataTransfer.effectAllowed = "move";
      });
    }

    for (let score of this.element.children) {
      score.addEventListener('dragover', event => {
        event.preventDefault();
        return true;
      });

      score.addEventListener('dragenter', event => {
        event.preventDefault();
      });

      score.addEventListener('drop', event => {
        let source = event.dataTransfer.getData("application/drag-id");
        if (source) {
          const token = document.querySelector('meta[name="csrf-token"]').content;

          source = document.getElementById(source);
          score.appendChild(source);

          let back = source.querySelector('span');
          back.style.opacity = 0.5;

          fetch(this.element.getAttribute('data-drop-action'), {
            method: 'POST',
            headers: {
              'X-CSRF-Token': token,
              'Content-Type': 'application/json'
            },
            credentials: 'same-origin',
            redirect: 'follow',
            body: JSON.stringify({
              heat: parseInt(source.id.replaceAll(/[^\d]/g, '')),
              score: score.dataset.score || ''
            })
          }).then (response => {
            back.style.opacity = 1;
            if (response.ok) {
              back.classList.remove('text-red-500')
            } else {
              back.classList.add('text-red-500')
            }
          })
        }
      })
    }
  }
}
