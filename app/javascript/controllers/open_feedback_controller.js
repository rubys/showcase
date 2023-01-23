import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="open-feedback"
export default class extends Controller {
  connect() {
    let previous = this.element.previousElementSibling;

    this.element.addEventListener('mouseenter', () => {
      previous.classList.add('bg-yellow-200');
    });

    this.element.addEventListener('mouseleave', () => {
      previous.classList.remove('bg-yellow-200');
    });

    for (let button of this.element.querySelectorAll('button')) {
      let span = button.querySelector('span');
      let abbr = button.querySelector('abbr');
      if (span && abbr) abbr.title = span.textContent;

      button.addEventListener('click', event => {
        for (let unselect of button.parentElement.querySelectorAll('button')) {
          if (unselect != button) unselect.classList.remove('selected');
        }
        button.classList.add('selected');
      })
    }
  }
}
