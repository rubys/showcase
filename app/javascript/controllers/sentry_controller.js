import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="sentry"
export default class extends Controller {
  async connect() {
    let response = await fetch('https://smooth-logger.fly.dev/sentry/seen')
    let text = await response.text()
    if (!text) return
    this.element.classList.add('bg-red-600')
    this.element.classList.add('text-white')
    this.element.href = new URL(text, 'https://smooth-logger.fly.dev/')
  }
}
