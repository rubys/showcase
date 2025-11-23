import { Controller } from "@hotwired/stimulus"

// Main controller for the heat scoring app
// Manages navigation between heat list and individual heat views
// Uses ERB-to-JS converted templates for rendering
export default class extends Controller {
  static values = {
    judge: Number,
    heat: Number,     // Optional - if provided, show heat; otherwise show list
    style: String,
    basePath: String
  }

  async connect() {
    console.log('HeatApp controller connected', {
      judge: this.judgeValue,
      heat: this.heatValue,
      style: this.styleValue
    })

    // Load converted ERB templates
    try {
      this.templates = await this.loadTemplates()
    } catch (error) {
      console.error('Failed to load templates:', error)
      this.showError(`Failed to load templates: ${error.message}`)
      return
    }

    // If heat number is provided, show that heat; otherwise show list
    if (this.hasHeatValue) {
      await this.showHeat(this.heatValue)
    } else {
      await this.showHeatList()
    }
  }

  async loadTemplates() {
    console.log('Loading converted ERB templates...')
    const response = await fetch('/templates/scoring.js')

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }

    const code = await response.text()

    // Parse the ES module code to extract template functions
    // The module exports: soloHeat, rankHeat, tableHeat, cardsHeat
    const module = await import(`data:text/javascript,${encodeURIComponent(code)}`)

    console.log('Templates loaded successfully')
    return module
  }

  async showHeatList() {
    console.log('Loading heat list...')

    try {
      // Fetch heat list data from JSON endpoint
      const response = await fetch(
        `${this.basePathValue}/scores/${this.judgeValue}/heats`
      )

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      console.log('Heat list data loaded:', data)

      // TODO: Render heat list using converted template
      this.element.innerHTML = '<h1>Heat List</h1><p>Coming soon...</p>'

    } catch (error) {
      console.error('Failed to load heat list:', error)
      this.showError(`Failed to load heat list: ${error.message}`)
    }
  }

  async showHeat(heatNumber) {
    console.log(`Loading heat ${heatNumber}...`)

    try {
      // Fetch heat data from new JSON endpoint
      const url = `${this.basePathValue}/scores/${this.judgeValue}/heats/${heatNumber}?style=${this.styleValue}`
      console.log('Fetching:', url)

      const response = await fetch(url)

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      console.log('Heat data loaded:', data)

      // Use the full heat template which will call appropriate partials
      console.log('Rendering full heat view with heat() template')
      const html = this.templates.heat(data)

      // Replace loading div with rendered heat
      this.element.innerHTML = html

      // Stimulus controllers (score, open-feedback, drop) will auto-attach!
      console.log('Heat rendered, Stimulus controllers should auto-attach')

    } catch (error) {
      console.error('Failed to load heat:', error)
      this.showError(`Failed to load heat: ${error.message}`)
    }
  }

  showError(message) {
    this.element.innerHTML = `
      <div class="flex items-center justify-center h-screen">
        <div class="text-center">
          <div class="text-2xl text-red-600 mb-4">Error</div>
          <div class="text-gray-700">${message}</div>
          <button onclick="location.reload()" class="mt-4 px-4 py-2 bg-blue-500 text-white rounded">
            Retry
          </button>
        </div>
      </div>
    `
  }
}
