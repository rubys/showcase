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

window.inject_region = function(headers) {
  if (document.body.dataset.machine) {
    return Object.assign({}, headers, {'Fly-Prefer-Instance-Id': document.body.dataset.machine})
  } else if (document.body.dataset.region) {
    return Object.assign({}, headers, {'Fly-Prefer-Region': document.body.dataset.region})
  } else {
    return headers
  }
}