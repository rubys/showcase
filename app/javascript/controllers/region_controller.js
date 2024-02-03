import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="region"
export default class extends Controller {
  connect() {
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
    event.detail.fetchOptions.headers['Fly-Prefer-Region'] = this.region;
  }
}

window.inject_region = function(headers) {
  if (document.body.dataset.region) {
    return Object.assign({}, headers, {'Fly-Prefer-Region': document.body.dataset.region})
  } else {
    return headers
  }
}