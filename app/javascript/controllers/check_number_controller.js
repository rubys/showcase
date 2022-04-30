import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="check-number"
export default class extends Controller {
  connect() {
    let checkboxes = this.element.querySelectorAll('input[type=checkbox]');
    for (let checkbox of [...checkboxes]) {
      checkbox.addEventListener("keydown", event => {
        let input = document.createElement('input');
        input.setAttribute('type', 'text');
        input.setAttribute('id', checkbox.getAttribute('id'));
        input.setAttribute('name', checkbox.getAttribute('name'));
        input.classList.add('entry-count');
        input.value = event.key;
        checkbox.replaceWith(input);
        input.blur();
        event.preventDefault();
      });
    }
  }
}