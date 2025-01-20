import { Controller } from "@hotwired/stimulus";

let pressTimer = null;

export function checkNumber(checkbox) {
  checkbox.addEventListener("change", _event => {
    checkbox.focus();  // needed for safari
  });

  checkbox.addEventListener('touchstart', event => {
    if (pressTimer) clearTimeout(pressTimer);
    if (checkbox.disabled) return;
    let input = createInput(checkbox);
    pressTimer = setTimeout(() => {
      input.value = checkbox.checked ? "1" : "0";
      checkbox.replaceWith(input);
      input.focus();
    }, 1000)
  });

  checkbox.addEventListener('touchend', event => {
    if (pressTimer) clearTimeout(pressTimer);
    pressTimer = null;
  });

  checkbox.addEventListener("keydown", event => {
    let input = createInput(checkbox);
    input.value = event.key;
    checkbox.replaceWith(input);
    input.focus();
    event.preventDefault();
  });
}

function createInput(checkbox) {
  let input = document.createElement("input");
  input.setAttribute("type", "text");
  input.setAttribute("id", checkbox.getAttribute("id"));
  input.setAttribute("name", checkbox.getAttribute("name"));
  input.setAttribute("autofocus", "autofocus");
  input.autofocus = true;
  input.classList.add("entry-count");
  return input;
}

// Connects to data-controller="check-number"
export default class extends Controller {
  connect() {
    let checkboxes = this.element.querySelectorAll("input[type=checkbox]");
    for (let checkbox of [...checkboxes]) {
      checkNumber(checkbox);
    }
  }
}