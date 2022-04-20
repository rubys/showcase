import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="affinity"
export default class extends Controller {
  connect() {
    this.affinities = JSON.parse(this.element.dataset.affinities);

    for (let select of this.element.querySelectorAll('select')) {
      select.addEventListener('input', event => {
        for (let [id, value] of Object.entries(this.affinities[select.value] || {})) {
          let element = document.getElementById(id);
          if (element && element.value == '') element.value = value;
        }
      })
    }
  }
}
