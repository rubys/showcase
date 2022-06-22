import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="formation"
export default class extends Controller {
  static targets = ["primary", "partner", "instructor"];

  connect() {
    this.boxes = [this.primaryTarget, this.partnerTarget].concat(this.instructorTargets);
    this.preventDupes();

    for (let box of this.boxes) {
      box.addEventListener('change', this.preventDupes);
      let option = document.createElement('option');
      option.textContent = '--delete--';
      option.setAttribute('value', 'x');
      box.appendChild(option);
    }

    let adds = this.element.querySelectorAll('div.absolute a');
    for (let add of adds) {
      add.addEventListener('click', event => {
        let lastBox = this.boxes[this.boxes.length - 1];
        if (lastBox.childElementCount >= this.boxes.length) {
          let box = lastBox.cloneNode(true);

          if (add.dataset.list) {
            for (let option of box.querySelectorAll('option')) {
              if (option.value != 'x') {
                option.remove();
              }
            }

            for (let [name, id] of Object.entries(JSON.parse(add.dataset.list)).reverse()) {
              if (name.includes(',')) {
                let parts = name.split(/,\s*/);
                name = [...parts.slice(-1), ...parts.slice(0, 1)].join(' ')
              }

              let option = document.createElement('option');
              option.value = id;
              option.textContent = name;
              box.prepend(option);
            }
          }

          box.id = box.id.replace(/\d+/, n => parseInt(n) + 1);
          box.setAttribute('name', box['name'].replace(/\d+/, n => parseInt(n) + 1));
          box.addEventListener('change', this.preventDupes);

          lastBox.parentNode.insertBefore(box, lastBox.nextSibling);
          this.boxes.push(box);
          this.preventDupes();
        }
      })
    }
  }

  preventDupes = (event) => {
    if (event && event.target.value == 'x') {
      event.target.remove();
      this.boxes = this.boxes.filter(item => item != event.target);
    }

    let taken = [];
    if (this.boxes.length <= 3) taken.push('x');
    for (let box of this.boxes) {
      for (let option of box.querySelectorAll('option')) {
        if (taken.includes(option.value)) {
          option.disabled = true;
          if (option.value == box.value) box.value = null;
        } else if (option.value == 'x') {
          if (!box.value) {
            this.boxes = this.boxes.filter(item => item != box);
            box.remove();
          }
        } else {
          option.disabled = false;
          if (!box.value || box.value == 'x') box.value = option.value;
        }
      }

      taken.push(box.value);
    }
  }
}
