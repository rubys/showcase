import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="info-box"
export default class extends Controller {
  connect() {
    let box = this.element.querySelector('.info-box');
    this.element.querySelector('.info-button').addEventListener('click', () => {
      if (box.style.display == 'block') {
        box.style.display = 'none';
      } else {
        box.style.display = 'block';
      }
    });
  }
}
