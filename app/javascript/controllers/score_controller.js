import { Controller } from "@hotwired/stimulus"

const HIGHLIGHT = 'bg-yellow-200';

// Connects to data-controller="score"
export default class extends Controller {
  static targets = ["error", "comments", "score"];

  keydown = event => {
    let form = false;
    if (this.hasCommentsTarget && this.commentsTarget == document.activeElement) form = true;
    for (let target of this.scoreTargets) {
      if (target == document.activeElement) form == true;
    }

    if (event.key == 'ArrowRight') {
      if (form) return;
      let link = document.querySelector('a[rel=next]')
      if (link) link.click();
    } else if (event.key == 'ArrowLeft') {
      if (form) return;
      let link = document.querySelector('a[rel=prev]')
      if (link) link.click();
    } else if (event.key == 'ArrowUp') {
      if (form) return;
      this.moveUp();
    } else if (event.key == 'ArrowDown') {
      this.moveDown();
    } else if (event.key == 'Escape') {
      this.unselect();
      this.unhighlight();
      if (document.activeElement) document.activeElement.blur();
    } else if (event.key == 'Tab') {
      event.preventDefault();
      event.stopPropagation();
      if (this.subjects.size > 0) {
        if (event.shiftKey) {
          this.prevSubject();
        } else {
          this.nextSubject();
        }
      } else if (this.hasCommentsTarget && document.activeElement == this.commentsTarget) {
        this.scoreTargets[0].focus();
      } else {
        let index = this.scoreTargets.findIndex(target => target == document.activeElement);
        if (this.hasCommentsTarget && (this.scoreTargets.length < 2 || index == -1)) {
          this.commentsTarget.focus();
        } else if (index == this.scoreTargets.length - 1) {
          this.scoreTargets[0].focus();
        } else {
          this.scoreTargets[index+1].focus();
        }
      }
    } else if (event.key == ' ' || event.key == 'Enter') {
      if (form) return;
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

  touchstart = event => {
    this.touchStart = event.touches[0];
  }

  touchend = event => {
    let direction = this.swipe(event);

    if (direction == 'right') {
      let link = document.querySelector('a[rel=prev]')
      if (link) link.click();
    } else if (direction == 'left') {
      let link = document.querySelector('a[rel=next]')
      if (link) link.click();
    } else if (direction == 'up') {
      let link = document.querySelector('a[rel=up]')
      if (link) link.click();
    }
  }

  swipe(event) {
    if (!this.touchStart) return false;
    let stop = event.changedTouches[0];
    if (stop.identifier != this.touchStart.identifier) return false;

    let deltaX = stop.clientX - this.touchStart.clientX;
    let deltaY = stop.clientY - this.touchStart.clientY;

    let height = document.documentElement.clientHeight;
    let width = document.documentElement.clientWidth;

    if (Math.abs(deltaX) > width/2 && Math.abs(deltaY) < height/4) {
      return deltaX > 0 ? "right" : "left"; 
    } else if (Math.abs(deltaY) > height/2 && Math.abs(deltaX) < width/4) {
      return deltaY > 0 ? "down" : "up";
    } else {
      return false;
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

  unhighlight() {
    for (let score of this.scores) {
      score.classList.remove(HIGHLIGHT)
    }
  }

  toggle(subject) {
    if (this.selected == subject) {
      this.unselect();
      this.unhighlight();
    } else {
      this.select(subject);
    }
  }

  nextSubject() {
    if (this.selected) {
      let back = this.selected.id;
      let backs = [...this.subjects.keys()];
      let index = backs.indexOf(back) + 1;
      if (index >= backs.length) {
        this.select(this.subjects.get(backs[0]));
      } else {
        this.select(this.subjects.get(backs[index]));
      }
    } else {
      let backs = [...this.subjects.keys()];
      this.select(this.subjects.get(backs[0]));
    }
  }

  prevSubject() {
    if (this.selected) {
      let back = this.selected.id;
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

    this.post({
      heat: parseInt(source.dataset.heat),
      slot: this.element.dataset.slot && parseInt(this.element.dataset.slot),
      score: score.dataset.score || ''
    }).then(response => {
      back.style.opacity = 1;
      if (response.ok) {
        back.classList.remove('text-red-500')
      } else {
        parent.appendChild(source);
        back.classList.add('text-red-500');
      }
    })
  }

  post = results => {
    return fetch(this.element.dataset.dropAction, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': this.token,
        'Content-Type': 'application/json'
      },
      credentials: 'same-origin',
      redirect: 'follow',
      body: JSON.stringify(results)
    }).then(response => {
      let error = this.errorTarget;

      if (response.ok) {
        error.style.display = 'none';
      } else {
        error.textContent = response.statusText;
        error.style.display = 'block';
      }

      return response;
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
    document.body.removeEventListener('touchstart', this.touchstart);
    document.body.removeEventListener('touchend', this.touchend);
  }

  connect() {
    this.token = document.querySelector('meta[name="csrf-token"]').content;

    this.subjects = [...this.element.querySelectorAll('*[draggable=true]')];

    let backs = this.subjects.map((element, index) => (
      {index, back: parseInt(element.querySelector('span').textContent || 1)}
    ));

    backs.sort((a, b) => {
      if (a.back > b.back) {
        return 1;
      } else if (b.back < a.back) {
        return -1;
      } else {
        return 0;
      }
    });

    this.subjects = new Map(backs.map(back => this.subjects[back.index])
      .map(element => [element.id, element])
    );

    this.scores = [...this.element.querySelectorAll('*[data-score]')];

    this.selected = null;
    this.mouseStart = null;

    document.body.addEventListener('keydown', this.keydown);
    document.body.addEventListener('touchstart', this.touchstart);
    document.body.addEventListener('touchend', this.touchend);

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
        this.unhighlight();
      });

      subject.addEventListener('touchend', event => {
        if (this.swipe(event)) return;
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

      score.addEventListener('touchend', event => {
        if (this.swipe(event)) return;
        event.preventDefault();
        this.move(this.selected, score)
        this.unhighlight();
      })
    }

    // mobile device viewport height is unreliable - use clientHeight
    let overflow = document.body.getBoundingClientRect().height - document.documentElement.clientHeight;
    if (overflow > 0) {
      let container = document.querySelector('.max-h-full');

      function resize() {
        container.style.maxHeight = `${document.documentElement.clientHeight}px`;
      }

      window.addEventListener("resize", resize);
      resize();
    }

    // wire up comments and scores for solos
    if (this.hasCommentsTarget) {
      this.commentsTarget.addEventListener('change', event => {
        this.commentsTarget.disabled = true;

        this.post({
          heat: parseInt(this.commentTarget.dataset.heat),
          test: 'data',
          comments: this.commentsTarget.value
        }).then(response => {
          this.commentsTarget.disabled = false;
          if (response.ok) {
            this.commentsTarget.style.backgroundColor = null;
          } else {
            this.commentsTarget.style.backgroundColor = '#F00';
          }
        })
      });
    }

    for (let button of this.element.querySelectorAll('input[type=radio]')) {
      button.addEventListener('change', event => {
        this.post({
          heat: parseInt(button.name),
          slot: this.element.dataset.slot && parseInt(this.element.dataset.slot),
          score: button.value
        }).then(response => {
          button.disabled = false;
          if (response.ok) {
            button.classList.remove('border-red-500')
          } else {
            parent.appendChild(source);
            button.classList.add('border-red-500');
          }
        })
      })
    }

    for (let target of this.scoreTargets) {
      target.addEventListener('change', event => {
        target.disabled = true;

        let data;
        if (this.hasCommentsTarget) {
          data = {
            heat: parseInt(this.commentsTarget.dataset.heat),
            score: target.value
          }
        } else {
          data = {
            heat: parseInt(target.name),
            slot: this.element.dataset.slot && parseInt(this.element.dataset.slot),
            score: target.value
          }
        }

        this.post(data).then(response => {
          target.disabled = false;
          if (response.ok) {
            target.style.backgroundColor = null;
          } else {
            target.style.backgroundColor = '#F00';
          }
        })
      });
    }
  }
}
