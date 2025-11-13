import { Controller } from "@hotwired/stimulus";

const HIGHLIGHT = "bg-yellow-200";

// Connects to data-controller="score"
export default class extends Controller {
  static targets = ["error", "comments", "score", "startButton"];

  callbacks = parseInt(this.element.dataset.callbacks);

  keydown = event => {
    let form = ["INPUT", "TEXTAREA"].includes(event.target.nodeName) ||
      ["INPUT", "TEXTAREA"].includes(document.activeElement.nodeName);

    if (event.key == "ArrowRight") {
      if (form) return;
      let link = document.querySelector("a[rel=next]");
      if (link) link.click();
    } else if (event.key == "ArrowLeft") {
      if (form) return;
      let link = document.querySelector("a[rel=prev]");
      if (link) link.click();
    } else if (event.key == "ArrowUp") {
      if (form) return;
      this.moveUp();
    } else if (event.key == "ArrowDown") {
      this.moveDown();
    } else if (event.key == "Escape") {
      this.unselect();
      this.unhighlight();
      if (document.activeElement) document.activeElement.blur();
    } else if (event.key == "Tab") {
      event.preventDefault();
      event.stopPropagation();
      if (this.subjects.size > 0) {
        if (event.shiftKey) {
          this.prevSubject();
        } else {
          this.nextSubject();
        }
      } else if (this.hasCommentsTarget && this.commentsTargets.includes(document.activeElement)) {
        if (this.commentsTargets.length > 1) {
          let index = this.commentsTargets.indexOf(document.activeElement) + 1;
          if (index >= this.commentsTargets.length) index = 0;
          this.commentsTargets[index].focus();
        } else {
          this.scoreTargets[0].focus();
        }
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
    } else if (event.key == " " || event.key == "Enter") {
      if (form) return;
      this.startHeat();
    }
  };

  touchstart = event => {
    this.touchStart = event.touches[0];
  };

  touchend = event => {
    let direction = this.swipe(event);

    if (direction == "right") {
      let link = document.querySelector("a[rel=prev]");
      if (link) link.click();
    } else if (direction == "left") {
      let link = document.querySelector("a[rel=next]");
      if (link) link.click();
    } else if (direction == "up") {
      let link = document.querySelector("a[rel=up]");
      if (link) link.click();
    }
  };

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
    this.selected.style.borderColor = "";
    this.selected.style.borderWidth = "";
    this.selected = null;
  }

  select(subject) {
    this.unselect();
    this.selected = subject;
    subject.style.borderColor = "black";
    subject.style.borderWidth = "3px";
  }

  unhighlight() {
    for (let score of this.scores) {
      score.classList.remove(HIGHLIGHT);
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
      let index = this.subjectOrder.indexOf(back) + 1;
      if (index >= this.subjectOrder.length) {
        this.select(this.subjects.get(this.subjectOrder[0]));
      } else {
        this.select(this.subjects.get(this.subjectOrder[index]));
      }
    } else {
      this.select(this.subjects.get(this.subjectOrder[0]));
    }
  }

  prevSubject() {
    if (this.selected) {
      let back = this.selected.id;
      let index = this.subjectOrder.indexOf(back) - 1;
      if (index < 0) {
        this.select(this.subjects.get(this.subjectOrder[this.subjectOrder.length - 1]));
      } else {
        this.select(this.subjects.get(this.subjectOrder[index]));
      }
    } else {
      this.select(this.subjects.get(this.subjectOrder[this.subjectOrder.length - 1]));
    }
  }

  move(source, score) {
    if (!source) return;
    let parent = source.parentElement;

    let back = source.querySelector("span");
    source.style.opacity = 1;
    back.style.opacity = 0.5;

    let before = [...score.children].find(child => (
      child.draggable && child.querySelector("span").textContent >= back.textContent
    ));

    if (before) {
      score.insertBefore(source, before);
    } else {
      score.appendChild(source);
    }

    this.post({
      heat: parseInt(source.dataset.heat),
      slot: this.element.dataset.slot && parseInt(this.element.dataset.slot),
      score: score.dataset.score || ""
    }).then(response => {
      back.style.opacity = 1;
      if (response.ok) {
        back.classList.remove("text-red-500");
      } else {
        parent.appendChild(source);
        back.classList.add("text-red-500");
      }
    });
  }

  post = results => {
    // If offline-capable attribute is present, skip fetch and return success
    // (the SPA will handle the actual save via HeatDataManager)
    if (this.element.dataset.offlineCapable === "true") {
      console.log('[score_controller] offline-capable detected, skipping fetch');
      return Promise.resolve({ ok: true });
    }

    console.log('[score_controller] Making fetch request, offlineCapable:', this.element.dataset.offlineCapable);

    return fetch(this.element.dataset.dropAction, {
      method: "POST",
      headers: window.inject_region({
        "X-CSRF-Token": this.token,
        "Content-Type": "application/json"
      }),
      credentials: "same-origin",
      redirect: "follow",
      body: JSON.stringify(results)
    }).then(response => {
      let error = this.errorTarget;

      if (response.ok) {
        error.style.display = "none";
      } else {
        error.textContent = response.statusText;
        error.style.display = "block";
      }

      return response;
    });
  };

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

  startHeat() {
    fetch(this.element.dataset.startAction, {
      method: "POST",
      headers: window.inject_region({
        "X-CSRF-Token": this.token,
        "Content-Type": "application/json"
      }),
      credentials: "same-origin",
      redirect: "follow",
      body: JSON.stringify({
        heat: parseInt(this.element.dataset.heat)
      })
    }).then(() => {
      if (this.hasStartButtonTarget) {
        this.startButtonTarget.style.display = "none";
      }
    });
  }

  checkIncompleteCallbacks = () => {
    // Check if we have callbacks enabled
    if (!this.callbacks) return false;

    // Count checked callbacks
    let checkedCount = this.element.querySelectorAll('input[type="checkbox"]:checked').length;

    // Return true if there are some callbacks checked but not exactly the expected number
    return checkedCount > 0 && checkedCount !== this.callbacks;
  };

  beforeUnload = event => {
    if (this.checkIncompleteCallbacks()) {
      event.preventDefault();
      event.returnValue = ''; // Required for Chrome
      return '';
    }
  };

  beforeVisit = event => {
    if (this.checkIncompleteCallbacks()) {
      if (!confirm('You have incomplete callbacks. Are you sure you want to leave this page?')) {
        event.preventDefault();
      }
    }
  };

  disconnect() {
    document.body.removeEventListener("keydown", this.keydown);
    document.body.removeEventListener("touchstart", this.touchstart);
    document.body.removeEventListener("touchend", this.touchend);
    window.removeEventListener("beforeunload", this.beforeUnload);
    document.documentElement.removeEventListener("turbo:before-visit", this.beforeVisit);
  }

  connect() {
    this.token = document.querySelector('meta[name="csrf-token"]').content;

    this.subjects = [...this.element.querySelectorAll("*[draggable=true]")];

    // Preserve the server-side ordering (which respects assignment priority)
    // instead of sorting by back number
    this.subjectOrder = this.subjects.map(element => element.id);
    this.subjects = new Map(this.subjects.map(element => [element.id, element]));

    this.scores = [...this.element.querySelectorAll("*[data-score]")];

    this.selected = null;
    this.mouseStart = null;

    document.body.addEventListener("keydown", this.keydown);
    document.body.addEventListener("touchstart", this.touchstart);
    document.body.addEventListener("touchend", this.touchend);
    window.addEventListener("beforeunload", this.beforeUnload);
    document.documentElement.addEventListener("turbo:before-visit", this.beforeVisit);

    for (let subject of this.subjects.values()) {
      if (!subject.dataset.heat) continue; // only for style="cards"; otherwise conflicts with skating finals

      subject.addEventListener("dragstart", event => {
        this.select(subject);
        subject.style.opacity = 0.4;
        event.dataTransfer.setData("application/drag-id", subject.id);
        event.dataTransfer.effectAllowed = "move";
      });

      subject.addEventListener("mouseup", event => {
        event.stopPropagation();
        this.toggle(subject);
        this.unhighlight();
      });

      subject.addEventListener("touchend", event => {
        if (this.swipe(event)) return;
        event.preventDefault();
        this.toggle(subject);
      });
    }

    for (let score of this.scores) {
      score.addEventListener("dragover", event => {
        event.preventDefault();
        return true;
      });

      score.addEventListener("dragenter", event => {
        score.classList.add(HIGHLIGHT);
        event.preventDefault();
      });

      score.addEventListener("mouseover", _event => {
        if (this.selected) score.classList.add(HIGHLIGHT);
      });

      score.addEventListener("mouseout", _event => {
        if (this.selected) score.classList.remove(HIGHLIGHT);
      });

      score.addEventListener("dragleave", _event => {
        score.classList.remove(HIGHLIGHT);
      });

      score.addEventListener("drop", event => {
        score.classList.remove(HIGHLIGHT);
        let source = event.dataTransfer.getData("application/drag-id");
        this.move(document.getElementById(source), score);
      });

      score.addEventListener("mouseup", _event => {
        this.move(this.selected, score);
      });

      score.addEventListener("touchend", event => {
        if (this.swipe(event)) return;
        event.preventDefault();
        this.move(this.selected, score);
        this.unhighlight();
      });
    }

    // mobile device viewport height is unreliable - use clientHeight
    let overflow = document.body.getBoundingClientRect().height - document.documentElement.clientHeight;
    if (overflow > 0) {
      let container = document.querySelector(".max-h-full");

      let resize= () => {
        if (!container) return;
        container.style.maxHeight = `${document.documentElement.clientHeight}px`;
      };

      window.addEventListener("resize", resize);
      resize();
    }

    // wire up comments and scores for solos and heats with comments enabled
    if (this.hasCommentsTarget) {
      this.commentTimeout = null;

      for (let comment of this.commentsTargets) {
        comment.disabled = false;

        comment.addEventListener("input", _event => {
          comment.classList.remove("bg-gray-50");
          comment.classList.add("bg-yellow-200");

          if (this.commentTimeout) clearTimeout(this.commentTimeout);

          this.commentTimeout = setTimeout(() => {
            if (comment.textarea !== comment.value) {
              comment.dispatchEvent(new Event("change"));
            }

            this.commentTimeout = null;
          }, 10000);
        });

        comment.addEventListener("change", _event => {
          comment.disabled = true;

          this.post({
            heat: parseInt(comment.dataset.heat),
            test: "data",
            comments: comment.value
          }).then(response => {
            comment.disabled = false;
            comment.classList.add("bg-gray-50");
            comment.classList.remove("bg-yellow-200");

            comment.textarea = comment.value;

            if (response.ok) {
              comment.style.backgroundColor = null;
            } else {
              comment.style.backgroundColor = "#F00";
            }
          });
        });
      }
    }

    for (let button of this.element.querySelectorAll("input[type=radio],input[type=checkbox]")) {
      button.disabled = false;

      button.addEventListener("change", event => {
        // enforce maximum number of callbacks
        if (
          this.callbacks && button.type === "checkbox" && button.checked &&
          this.element.querySelectorAll('input[type="checkbox"]:checked').length > this.callbacks
        ) {
          event.preventDefault();
          event.stopPropagation();
          button.checked = false;
          return;
        }

        this.post({
          heat: parseInt(button.name),
          slot: this.element.dataset.slot && parseInt(this.element.dataset.slot),
          score: button.type == "radio" ? button.value : (button.checked ? 1 : "")
        }).then(response => {
          button.disabled = false;
          if (response.ok) {
            button.classList.remove("border-red-500");
          } else {
            button.classList.add("border-red-500");
          }
        });
      });
    }

    for (let target of this.scoreTargets) {
      target.disabled = false;

      target.addEventListener("change", _event => {
        target.disabled = true;

        let data;
        if (this.commentsTargets.length == 1) {
          data = {
            heat: parseInt(this.commentsTarget.dataset.heat),
            score: target.value
          };
        } else {
          data = {
            heat: parseInt(target.name),
            slot: this.element.dataset.slot && parseInt(this.element.dataset.slot),
            score: target.value
          };
        }

        if (target.name) {
          data.name = target.name;
        }

        this.post(data).then(response => {
          target.disabled = false;
          if (response.ok) {
            target.style.backgroundColor = null;
          } else {
            target.style.backgroundColor = "#F00";
          }
        });
      });
    }
    // auto resize tabular (open, closed) textarea comments
    for (let textarea of document.querySelectorAll("table textarea")) {
      if (!textarea.dataset.scoreTarget === "comments") continue;
      textarea.rows = 1;
      textarea.style.height = textarea.scrollHeight + "px";

      textarea.addEventListener("input", () => {
        textarea.style.height = 0;
        textarea.style.height = textarea.scrollHeight + "px";
      });
    }
  }
}
