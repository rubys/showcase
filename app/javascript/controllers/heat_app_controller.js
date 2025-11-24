import { Controller } from "@hotwired/stimulus"
import { buildLookupTables, hydrateHeat, buildHeatTemplateData } from "lib/heat_hydrator"

// Main controller for the heat scoring SPA
// Loads normalized data once, then handles navigation client-side
export default class extends Controller {
  static values = {
    judge: Number,
    heat: Number,     // Optional - if provided, show heat; otherwise show list
    style: String,
    basePath: String
  }

  async connect() {
    console.debug('HeatApp controller connected', {
      judge: this.judgeValue,
      heat: this.heatValue,
      style: this.styleValue
    })

    // Listen for browser back/forward navigation
    this.popstateHandler = this.handlePopState.bind(this)
    window.addEventListener('popstate', this.popstateHandler)

    // Load converted ERB templates
    try {
      this.templates = await this.loadTemplates()
    } catch (error) {
      console.error('Failed to load templates:', error)
      this.showError(`Failed to load templates: ${error.message}`)
      return
    }

    // Load all normalized data once
    try {
      await this.loadAllData()
    } catch (error) {
      console.error('Failed to load data:', error)
      this.showError(`Failed to load data: ${error.message}`)
      return
    }

    // If heat number is provided, show that heat; otherwise show list
    if (this.hasHeatValue) {
      this.showHeat(this.heatValue)
    } else {
      this.showHeatList()
    }
  }

  disconnect() {
    // Clean up event listener
    window.removeEventListener('popstate', this.popstateHandler)
  }

  handlePopState(event) {
    // Handle browser back/forward buttons
    const url = new URL(window.location)
    const heatParam = url.searchParams.get('heat')

    if (heatParam) {
      const heatNumber = parseFloat(heatParam)
      this.heatValue = heatNumber
      this.showHeat(heatNumber)
    }
  }

  async loadTemplates() {
    console.debug('Loading converted ERB templates...')
    // Use full URL path instead of bare specifier
    const module = await import(`${this.basePathValue}/templates/scoring.js`)

    console.debug('Templates loaded successfully')
    return module
  }

  async loadAllData() {
    console.debug('Loading normalized data...')
    const response = await fetch(
      `${this.basePathValue}/scores/${this.judgeValue}/heats/data`
    )

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }

    const data = await response.json()
    console.debug('Normalized data loaded:', {
      heats: data.heats.length,
      people: Object.keys(data.people).length,
      studios: Object.keys(data.studios).length,
      entries: Object.keys(data.entries).length,
      maxHeatNumber: Math.max(...data.heats.map(h => h.number)),
      minHeatNumber: Math.min(...data.heats.map(h => h.number))
    })

    // Store raw normalized data
    this.rawData = data

    // Build lookup tables for fast access
    this.buildLookupTables()

    console.debug('Data hydration complete')
  }

  buildLookupTables() {
    // Use shared hydration logic
    const lookups = buildLookupTables(this.rawData)

    // Store lookups as instance properties for backward compatibility
    this.people = lookups.people
    this.studios = lookups.studios
    this.entries = lookups.entries
    this.dances = lookups.dances
    this.ages = lookups.ages
    this.levels = lookups.levels
    this.solos = lookups.solos
    this.formations = lookups.formations
    this.scores = lookups.scores
    this.heatsByNumber = lookups.heatsByNumber
  }

  // Hydrate a single heat - convert IDs to full objects
  // Uses shared hydration logic from heat_hydrator.js
  hydrateHeat(heat) {
    const lookups = {
      people: this.people,
      studios: this.studios,
      entries: this.entries,
      dances: this.dances,
      ages: this.ages,
      levels: this.levels,
      solos: this.solos,
      formations: this.formations,
      scores: this.scores
    }
    return hydrateHeat(heat, lookups)
  }

  showHeatList() {
    console.debug('Rendering heat list...')

    try {
      // Use raw data but group heats by number (matching ERB .group(:number) behavior)
      const data = { ...this.rawData }

      // Group heats by number and take first heat for each number
      const heatsByNumber = {}
      data.heats.forEach(heat => {
        if (!heatsByNumber[heat.number]) {
          heatsByNumber[heat.number] = heat
        }
      })
      data.heats = Object.values(heatsByNumber)

      console.debug(`Rendering heat list with ${data.heats.length} unique heat numbers`)

      // Render using converted heatlist template
      const html = this.templates.heatlist(data)

      // Replace content
      this.element.innerHTML = html

      // Intercept clicks on heat links to navigate within SPA
      this.attachHeatListListeners()

      console.debug('Heat list rendered successfully')

    } catch (error) {
      console.error('Failed to render heat list:', error)
      this.showError(`Failed to render heat list: ${error.message}`)
    }
  }

  attachHeatListListeners() {
    // Intercept clicks on heat links to navigate within SPA
    this.element.querySelectorAll('a[href*="/heat/"]').forEach(link => {
      link.addEventListener('click', (e) => {
        e.preventDefault()
        const url = new URL(link.href, window.location.origin)
        const heatMatch = url.pathname.match(/\/heat\/(\d+\.?\d*)/)
        if (heatMatch) {
          const heatNumber = parseFloat(heatMatch[1])
          this.navigateToHeat(heatNumber)
        }
      })
    })

    // Forms and other links remain functional via Turbo (will cause page navigation)
    // This is acceptable - forms don't need to work offline
  }

  showHeat(heatNumber) {
    console.debug(`Rendering heat ${heatNumber}...`)

    try {
      // Use shared template data building logic
      const data = buildHeatTemplateData(heatNumber, this.rawData, this.styleValue)

      console.debug('Rendering heat with hydrated data')
      console.debug(`Data summary: subjects=${data.subjects.length}, show=${data.show}, assign_judges=${data.assign_judges}, category_scoring=${data.category_scoring_enabled}, assignments=${data.category_score_assignments.length}`)

      const html = this.templates.heat(data)

      // Replace content with rendered heat
      this.element.innerHTML = html

      // Stimulus controllers (score, open-feedback, drop) will auto-attach!
      console.debug('Heat rendered successfully')

    } catch (error) {
      console.error('Failed to render heat:', error)
      this.showError(`Failed to render heat: ${error.message}`)
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

  // Navigation methods for prev/next heat links
  navigatePrev(event) {
    event.preventDefault()
    const allHeatNumbers = Object.keys(this.heatsByNumber).map(n => parseFloat(n)).sort((a, b) => a - b)
    const currentHeat = parseFloat(this.heatValue)
    const currentIndex = allHeatNumbers.indexOf(currentHeat)

    if (currentIndex > 0) {
      const prevHeat = allHeatNumbers[currentIndex - 1]
      this.navigateToHeat(prevHeat)
    }
  }

  navigateNext(event) {
    event.preventDefault()
    const allHeatNumbers = Object.keys(this.heatsByNumber).map(n => parseFloat(n)).sort((a, b) => a - b)
    const currentHeat = parseFloat(this.heatValue)
    const currentIndex = allHeatNumbers.indexOf(currentHeat)

    if (currentIndex < allHeatNumbers.length - 1) {
      const nextHeat = allHeatNumbers[currentIndex + 1]
      this.navigateToHeat(nextHeat)
    }
  }

  navigateToHeat(heatNumber) {
    console.debug(`Navigating to heat ${heatNumber}`)

    // Update the URL
    const url = new URL(window.location)
    url.searchParams.set('heat', heatNumber)
    window.history.pushState({}, '', url)

    // Update the Stimulus value which will trigger re-render
    this.heatValue = heatNumber

    // Render the new heat
    this.showHeat(heatNumber)
  }
}
