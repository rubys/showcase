import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="region"
export default class extends Controller {
  connect() {
    this.machine = this.element.dataset.machine;
    this.region = this.element.dataset.region;

    document.documentElement.addEventListener(
     'turbo:before-fetch-request',
     this.beforeFetchRequest
    )
  }

  disconnect() {
    document.documentElement.removeEventListener(
     'turbo:before-fetch-request',
     this.beforeFetchRequest
    )
  }

  beforeFetchRequest = event => {
    if (this.machine) {
      event.detail.fetchOptions.headers['Fly-Prefer-Instance-Id'] = this.machine;
    } else if (this.region) {
      event.detail.fetchOptions.headers['Fly-Prefer-Region'] = this.region;
    }
  }
}