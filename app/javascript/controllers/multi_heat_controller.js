import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="multi-heat"
export default class extends Controller {
  connect() {
    let checkboxes = this.element.querySelectorAll('input[type=checkbox]');
    for (let checkbox of [...checkboxes]) {
      checkbox.addEventListener("keydown", event => {
        for (let checkbox of [...checkboxes]) {
          let input = document.createElement('input');
          input.setAttribute('type', 'text');
          input.setAttribute('id', checkbox.getAttribute('id'));
          input.setAttribute('name', checkbox.getAttribute('name'));
          input.classList.add('entry-count');
          if (checkbox == event.target) {
            input.value = event.key;
          } else if (checkbox.checked) {
            input.value = checkbox.value;
          }
          checkbox.replaceWith(input);
          input.blur();
          event.preventDefault();
        }
      });
    }
  }
}
