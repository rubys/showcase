import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="live-scores"
export default class extends Controller {
  connect() {
    this.token = document.querySelector('meta[name="csrf-token"]').content;

    const observer = new MutationObserver(this.reload);
    const config = { attributes: true, childList: true, subtree: true };
    observer.observe(this.element, config);
  }

  reload = event => {
    fetch(this.element.getAttribute('action'), {
      method: 'POST',
      headers: {
	'X-CSRF-Token': this.token,
	'Content-Type': 'application/json'
      },
      credentials: 'same-origin',
      redirect: 'follow',
      body: ''
    }).then (response => response.text())
    .then(html => Turbo.renderStreamMessage(html));
  }
}
