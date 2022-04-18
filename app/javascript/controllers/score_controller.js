import { Controller } from "@hotwired/stimulus"

const HIGHLIGHT = 'bg-yellow-200';

// Connects to data-controller="score"
export default class extends Controller {
  static targets = ["error"]

  keydown = event => {
    if (event.key == 'ArrowRight') {
      let link = document.querySelector('a[rel=next]')
      if (link) link.click();
    } else if (event.key == 'ArrowLeft') {
      let link = document.querySelector('a[rel=prev]')
      if (link) link.click();
    } else if (event.key == 'ArrowUp') {
      this.moveUp();
    } else if (event.key == 'ArrowDown') {
      this.moveDown();
    } else if (event.key == 'Escape') {
      this.unselect();
    } else if (event.key == 'Tab') {
      event.preventDefault();
      event.stopPropagation();
      if (event.shiftKey) {
        this.prevSubject();
      } else {
        this.nextSubject();
      }
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

  unselect() {
    if (!this.selected) return;
    this.selected.style.borderColor = '';
    this.selected.style.borderWidth = '';
    this.selected = null;
  }

  select(subject) {
    this.unselect();
    this.selected = subject;
    subject.style.borderColor = 'black';
    subject.style.borderWidth = '3px';
  }

  toggle(subject) {
    if (this.selected == subject) {
      this.unselect();

      for (let score of this.scores) {
        score.classList.remove(HIGHLIGHT)
      }
    } else {
      this.select(subject);
    }
  }

  nextSubject() {
    if (this.selected) {
      let back = parseInt(this.selected.querySelector('span').textContent || 1);
      let backs = [...this.subjects.keys()].sort();
      let index = backs.indexOf(back) + 1;
      if (index >= backs.length) {
        this.select(this.subjects.get(backs[0]));
      } else {
        this.select(this.subjects.get(backs[index]));
      }
    } else {
      let backs = [...this.subjects.keys()].sort();
      this.select(this.subjects.get(backs[0]));
    }
  }

  prevSubject() {
    if (this.selected) {
      let back = parseInt(this.selected.querySelector('span').textContent || 1);
      let backs = [...this.subjects.keys()].sort();
      let index = backs.indexOf(back) - 1;
      if (index < 0) {
        this.select(this.subjects.get(backs[backs.length - 1]));
      } else {
        this.select(this.subjects.get(backs[index]));
      }
    } else {
      let backs = [...this.subjects.keys()].sort();
      this.select(this.subjects.get(backs[backs.length - 1]));
    }
  }

  move(source, score) {
    if (!source) return;
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
    }).then(response => {
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

  moveUp() {
    if (!this.selected) return;
    let index = this.scores.indexOf(this.selected.parentElement);

    if (index > 0) {
      this.move(this.selected, this.scores[index - 1]);
    } else {
      this.move(this.selected, this.scores[this.scores.length - 1]);
    }
  }

  moveDown() {
    if (!this.selected) return;
    let index = this.scores.indexOf(this.selected.parentElement);

    if (index + 1 == this.scores.length) {
      this.move(this.selected, this.scores[0]);
    } else {
      this.move(this.selected, this.scores[index + 1]);
    }
  }

  disconnect() {
    document.body.removeEventListener('keydown', this.keydown);
  }

  connect() {
    this.token = document.querySelector('meta[name="csrf-token"]').content;

    this.subjects = new Map([...this.element.querySelectorAll('*[draggable=true]')]
      .map(element =>
        [parseInt(element.querySelector('span').textContent || 1), element]
      )
    );

    this.scores = [...this.element.querySelectorAll('*[data-score]')];

    this.selected = null;

    document.body.addEventListener('keydown', this.keydown);

    for (let subject of this.subjects.values()) {
      subject.addEventListener('dragstart', event => {
        this.select(subject);
        subject.style.opacity = 0.4;
        event.dataTransfer.setData('application/drag-id', subject.id);
        event.dataTransfer.effectAllowed = "move";
      });

      subject.addEventListener('mouseup', event => {
        event.stopPropagation();
        this.toggle(subject);
      });

      subject.addEventListener('touchend', event => {
        event.preventDefault();
        this.toggle(subject);
      });
    }

    for (let score of this.scores) {
      score.addEventListener('dragover', event => {
        event.preventDefault();
        return true;
      });

      score.addEventListener('dragenter', event => {
        score.classList.add(HIGHLIGHT);
        event.preventDefault();
      });

      score.addEventListener('mouseover', event => {
        if (this.selected) score.classList.add(HIGHLIGHT);
      });

      score.addEventListener('mouseout', event => {
        if (this.selected) score.classList.remove(HIGHLIGHT);
      });

      score.addEventListener('dragleave', event => {
        score.classList.remove(HIGHLIGHT);
      });

      score.addEventListener('drop', event => {
        score.classList.remove(HIGHLIGHT);
        let source = event.dataTransfer.getData("application/drag-id");
        this.move(document.getElementById(source), score);
      })

      score.addEventListener('mouseup', event => {
        this.move(this.selected, score)
      })
    }

    // iPad viewport height is unreliable - use clientHeight
    let overflow = document.body.getBoundingClientRect().height - window.innerHeight;
    if (overflow > 0) {
      let container = document.querySelector('.max-h-full');

      function resize() {
        container.style.maxHeight = `${document.documentElement.clientHeight}px`;
      }

      window.addEventListener("resize", resize);
      resize();
    }
  }
}
