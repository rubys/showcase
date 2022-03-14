import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="score"
export default class extends Controller {
  static targets = [ "error" ]

  keydown = event => {
    if (event.key == 'ArrowRight') {
      let link = document.querySelector('a[rel=next]')
      if (link) link.click();
    } else if (event.key == 'ArrowLeft') {
      let link = document.querySelector('a[rel=prev]')
      if (link) link.click();
    } else if (event.key == ' ' || event.key == 'Enter') {
      fetch(this.element.dataset.startAction, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.token,
          'Content-Type': 'application/json'
        },
        credentials: 'same-origin',
        redirect: 'follow',
        body: JSON.stringify({
          heat: parseInt(this.element.dataset.heat)
        })
      })
    }
  }

  disconnect() {
    document.body.removeEventListener('keydown', this.keydown);
  }

  connect() {
    this.token = document.querySelector('meta[name="csrf-token"]').content;

    document.body.addEventListener('keydown', this.keydown);

    for (let subject of this.element.querySelectorAll('*[draggable=true]')) {
      subject.addEventListener('dragstart', event => {
        subject.style.opacity = 0.4;
        event.dataTransfer.setData('application/drag-id', subject.id);
        event.dataTransfer.effectAllowed = "move";
      });
    }

    for (let score of this.element.querySelectorAll('*[data-score]')) {
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
          source = document.getElementById(source);
          let parent = source.parentElement;

          let back = source.querySelector('span');
          source.style.opacity = 1;
          back.style.opacity = 0.5;

          let before = [...score.children].find(child => (
            child.draggable && child.querySelector('span').textContent >= back.textContent
          ));

          if (before) {
            score.insertBefore(source, before);
          } else {
            score.appendChild(source);
          }

          let error = this.errorTarget;

          fetch(this.element.dataset.dropAction, {
            method: 'POST',
            headers: {
              'X-CSRF-Token': this.token,
              'Content-Type': 'application/json'
            },
            credentials: 'same-origin',
            redirect: 'follow',
            body: JSON.stringify({
              heat: parseInt(source.dataset.heat),
              score: score.dataset.score || ''
            })
          }).then (response => {
            back.style.opacity = 1;
            if (response.ok) {
              error.style.display = 'none';
              back.classList.remove('text-red-500')
            } else {
              parent.appendChild(source);
              error.textContent = response.statusText;
              error.style.display = 'block';
              back.classList.add('text-red-500')
            }
          })
        }
      })
    }
  }
}
