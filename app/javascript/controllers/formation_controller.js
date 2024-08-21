import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="formation"
export default class extends Controller {
  static targets = ["primary", "partner", "instructor"];

  connect() {
    this.students = [...this.partnerTarget.querySelectorAll("option")].map(option => option.value);
    this.instructors = [...this.instructorTarget.querySelectorAll("option")].map(option => option.value);

    this.boxes = [this.primaryTarget, this.partnerTarget].concat(this.instructorTargets);
    this.preventDupes();

    // if there is only one instructor, that instructor can't be the partner
    if (this.instructors.length == 1) {
      for (let option of this.partnerTarget.querySelectorAll("option")) {
        if (option.value == this.instructors[0]) {
          option.disabled = true;
        }
      }
    }

    for (let box of this.boxes) {
      box.addEventListener("change", this.preventDupes);
      let option = document.createElement("option");
      option.textContent = "--delete--";
      option.setAttribute("value", "x");
      if (box == this.instructorTarget || box == this.partnerTarget) option.disabled = true;
      box.appendChild(option);
    }

    let adds = this.element.querySelectorAll("div.absolute a");
    for (let add of adds) {
      add.addEventListener("click", _event => {
        if (add.style.opacity) return;

        let lastBox = this.boxes[this.boxes.length - 1];

        let base = add.textContent.includes("instructor") ? this.instructorTarget : this.partnerTarget;

        let box = base.cloneNode(true);
        box.classList.remove("hidden");
        box.disabled = false;

        if (add.dataset.list) {
          for (let option of box.querySelectorAll("option")) {
            if (option.value != "x") {
              option.remove();
            } else {
              option.disabled = false;
            }
          }

          for (let [name, id] of Object.entries(JSON.parse(add.dataset.list)).reverse()) {
            if (name.includes(",")) {
              let parts = name.split(/,\s*/);
              name = [...parts.slice(-1), ...parts.slice(0, 1)].join(" ");
            }

            let option = document.createElement("option");
            option.value = id;
            option.textContent = name;
            box.prepend(option);
          }
        }

        box.id = `solo_formation[${this.boxes.length - 1}]`;
        box.setAttribute("name", `solo[formation][${this.boxes.length}]`);
        box.removeAttribute("data-formation-target");
        box.addEventListener("change", this.preventDupes);

        lastBox.parentNode.insertBefore(box, lastBox.nextSibling);
        this.boxes.push(box);
        this.preventDupes();

        if ([...box.children].every(child => child.disabled || child.value === "x")) {
          this.boxes.pop().remove();
        }
      });
    }
  }

  preventDupes = (event) => {
    if (event && event.target.value == "x") {
      event.target.remove();
      this.boxes = this.boxes.filter(item => item != event.target);
    }

    let taken = [];
    if (this.boxes.length <= 3) taken.push("x");
    for (let box of this.boxes) {
      if (box.classList.contains("hidden") || box.disabled) continue;
      let avail = "";
      let options = box.querySelectorAll("option");
      for (let option of options) {
        if (taken.includes(option.value)) {
          option.disabled = true;
          if (option.value == box.value) box.value = avail;
        } else if (option.value == "x") {
          if (!box.value) {
            let option = [...options].find(option => !option.disabled && option.value !== "x");
            if (option) {
              box.value = option.value;
            } else {
              this.boxes = this.boxes.filter(item => item != box);
              box.remove();
            }
          }
        } else {
          option.disabled = false;
          avail ||= option.value;
          if (!box.value && box.value == "x") box.value = avail;
        }
      }

      taken.push(box.value);
    }

    let adds = this.element.querySelectorAll("div.absolute a");

    if (this.instructors.every(instructor => taken.includes(instructor))) {
      adds[0].style.cursor = "not-allowed";
      adds[0].style.opacity = "50%";
    } else {
      adds[0].style.cursor = "";
      adds[0].style.opacity = "";
    }

    if (adds[1]) {
      if (this.students.every(student => taken.includes(student) || this.instructors.includes(student))) {
        adds[1].style.cursor = "not-allowed";
        adds[1].style.opacity = "50%";
      } else {
        adds[1].style.cursor = "";
        adds[1].style.opacity = "";
      }
    }
  };
}
