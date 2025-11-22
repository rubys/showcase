import { Controller } from "@hotwired/stimulus"

// Main controller for the heat scoring app
// Manages navigation between heat list and individual heat views
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

    // If heat number is provided, show that heat; otherwise show list
    if (this.hasHeatValue) {
      await this.showHeat(this.heatValue)
    } else {
      await this.showHeatList()
    }
  }

  async showHeatList() {
    console.log('Loading heat list...')

    try {
      // Fetch heat list data from JSON endpoint
      const response = await fetch(
        `${this.basePathValue}/scores/${this.judgeValue}/heats.json`
      )

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      console.log('Heat list data loaded:', data)

      // Render heat list (TODO: implement heat list rendering)
      this.element.innerHTML = '<h1>Heat List</h1><p>Coming soon...</p>'

    } catch (error) {
      console.error('Failed to load heat list:', error)
      this.showError(`Failed to load heat list: ${error.message}`)
    }
  }

  async showHeat(heatNumber) {
    console.log(`Loading heat ${heatNumber}...`)

    try {
      // Fetch heat data from JSON endpoint
      const response = await fetch(
        `${this.basePathValue}/scores/${this.judgeValue}/heat/${heatNumber}.json?style=${this.styleValue}`
      )

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      console.log('Heat data loaded:', data)

      // Render heat (TODO: implement heat rendering)
      this.element.innerHTML = '<h1>Heat View</h1><p>Coming soon...</p>'

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
