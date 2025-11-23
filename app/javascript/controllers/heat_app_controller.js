import { Controller } from "@hotwired/stimulus"

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

  async loadTemplates() {
    console.log('Loading converted ERB templates...')
    const response = await fetch('/templates/scoring.js')

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }

    const code = await response.text()
    const module = await import(`data:text/javascript,${encodeURIComponent(code)}`)

    console.log('Templates loaded successfully')
    return module
  }

  async loadAllData() {
    console.log('Loading normalized data...')
    const response = await fetch(
      `${this.basePathValue}/scores/${this.judgeValue}/heats/data`
    )

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }

    const data = await response.json()
    console.log('Normalized data loaded:', {
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

    console.log('Data hydration complete')
  }

  buildLookupTables() {
    // Store lookup tables for O(1) access
    this.people = this.rawData.people
    this.studios = this.rawData.studios
    this.entries = this.rawData.entries
    this.dances = this.rawData.dances
    this.ages = this.rawData.ages
    this.levels = this.rawData.levels
    this.solos = this.rawData.solos
    this.formations = this.rawData.formations
    this.scores = this.rawData.scores

    // Build heats by number for easy lookup
    this.heatsByNumber = {}
    this.rawData.heats.forEach(heat => {
      if (!this.heatsByNumber[heat.number]) {
        this.heatsByNumber[heat.number] = []
      }
      this.heatsByNumber[heat.number].push(heat)
    })
  }

  // Hydrate a single heat - convert IDs to full objects
  hydrateHeat(heat) {
    const hydrated = { ...heat }

    // Hydrate dance
    if (heat.dance_id && this.dances[heat.dance_id]) {
      hydrated.dance = this.dances[heat.dance_id]
    }

    // Hydrate entry
    if (heat.entry_id && this.entries[heat.entry_id]) {
      const entry = { ...this.entries[heat.entry_id] }

      // Hydrate lead
      if (entry.lead_id && this.people[entry.lead_id]) {
        const lead = { ...this.people[entry.lead_id] }
        if (lead.studio_id && this.studios[lead.studio_id]) {
          lead.studio = this.studios[lead.studio_id]
        }
        entry.lead = lead
      }

      // Hydrate follow
      if (entry.follow_id && this.people[entry.follow_id]) {
        const follow = { ...this.people[entry.follow_id] }
        if (follow.studio_id && this.studios[follow.studio_id]) {
          follow.studio = this.studios[follow.studio_id]
        }
        entry.follow = follow
      }

      // Hydrate instructor
      if (entry.instructor_id && this.people[entry.instructor_id]) {
        const instructor = { ...this.people[entry.instructor_id] }
        if (instructor.studio_id && this.studios[instructor.studio_id]) {
          instructor.studio = this.studios[instructor.studio_id]
        }
        entry.instructor = instructor
      }

      // Hydrate age and level
      if (entry.age_id && this.ages[entry.age_id]) {
        entry.age = this.ages[entry.age_id]
      }
      if (entry.level_id && this.levels[entry.level_id]) {
        entry.level = this.levels[entry.level_id]
      }

      hydrated.entry = entry

      // Add lead/follow/subject at top level for template compatibility
      if (entry.lead) {
        hydrated.lead = entry.lead
      }
      if (entry.follow) {
        hydrated.follow = entry.follow
      }
      // Subject is the student in student/professional pairings
      if (entry.lead && entry.lead.type === 'Student') {
        hydrated.subject = entry.lead
      } else if (entry.follow && entry.follow.type === 'Student') {
        hydrated.subject = entry.follow
      }
    }

    // Hydrate solo
    if (heat.solo_id && this.solos[heat.solo_id]) {
      hydrated.solo = { ...this.solos[heat.solo_id] }

      // Hydrate formations for this solo
      hydrated.solo.formations = Object.values(this.formations)
        .filter(f => f.solo_id === heat.solo_id)
        .map(formation => {
          const f = { ...formation }
          if (f.person_id && this.people[f.person_id]) {
            const person = { ...this.people[f.person_id] }
            if (person.studio_id && this.studios[person.studio_id]) {
              person.studio = this.studios[person.studio_id]
            }
            f.person = person
          }
          return f
        })
    }

    // Hydrate scores
    hydrated.scores = Object.values(this.scores)
      .filter(s => s.heat_id === heat.id)

    return hydrated
  }

  showHeatList() {
    console.log('Rendering heat list...')
    // TODO: Implement heat list view
    this.element.innerHTML = '<h1>Heat List</h1><p>Coming soon...</p>'
  }

  showHeat(heatNumber) {
    console.log(`Rendering heat ${heatNumber}...`)
    console.log(`Type of heatNumber: ${typeof heatNumber}, value: ${heatNumber}`)

    try {
      // Find heats with this number
      // Try both string and number lookup since JavaScript object keys can be tricky
      let heats = this.heatsByNumber[heatNumber] ||
                  this.heatsByNumber[parseFloat(heatNumber)] ||
                  this.heatsByNumber[String(heatNumber)]

      if (!heats || heats.length === 0) {
        console.error('Looking for heat:', heatNumber, typeof heatNumber)
        console.error('Available heat numbers (first 10):', Object.keys(this.heatsByNumber).slice(0, 10))
        console.error('Sample lookup:', this.heatsByNumber[1], this.heatsByNumber['1'], this.heatsByNumber[1.0])
        throw new Error(`Heat ${heatNumber} not found`)
      }

      // Hydrate all heats with this number
      const hydratedHeats = heats.map(h => this.hydrateHeat(h))

      // Get primary heat for main properties
      const primaryHeat = hydratedHeats[0]
      const event = this.rawData.event
      const dance = primaryHeat.dance

      // Determine scoring type (matches logic from heats_show)
      const category = primaryHeat.category
      let scoring
      if (category === 'Solo') {
        scoring = event.solo_scoring
      } else if (category === 'Multi') {
        scoring = event.multi_scoring
      } else if (category === 'Open' || (category === 'Closed' && event.closed_scoring === '=') || event.heat_range_cat > 0) {
        scoring = event.open_scoring
      } else {
        scoring = event.closed_scoring
      }

      // Group subjects by ballroom (matches logic from heat controller action)
      const ballrooms = {}
      let ballroomsCount = 0
      hydratedHeats.forEach(heat => {
        const ballroom = heat.ballroom || 1
        if (!ballrooms[ballroom]) {
          ballrooms[ballroom] = []
          ballroomsCount++
        }
        ballrooms[ballroom].push(heat)
      })

      // Determine final and callbacks flags
      const final = dance.uses_scrutineering && scoring.startsWith('rank')
      const callbacks = dance.uses_scrutineering && scoring === 'check'

      // Calculate prev/next heat numbers
      const allHeatNumbers = Object.keys(this.heatsByNumber).map(n => parseFloat(n)).sort((a, b) => a - b)
      const currentIndex = allHeatNumbers.indexOf(parseFloat(heatNumber))
      const prev = currentIndex > 0 ? allHeatNumbers[currentIndex - 1] : null
      const next = currentIndex < allHeatNumbers.length - 1 ? allHeatNumbers[currentIndex + 1] : null
      console.log(`Navigation: prev=${prev}, next=${next}, currentIndex=${currentIndex}, total=${allHeatNumbers.length}`)

      // Build score lookup objects (value, good, bad, comments by subject id)
      const value = {}
      const good = {}
      const bad = {}
      const comments = {}
      const scores = []

      hydratedHeats.forEach(heat => {
        if (heat.scores && heat.scores.length > 0) {
          heat.scores.forEach(score => {
            const subjectId = heat.id
            value[subjectId] = score.value
            good[subjectId] = score.good
            bad[subjectId] = score.bad
            if (score.comments) {
              comments[subjectId] = score.comments
            }
            scores.push(score)
          })
        }
      })

      // Build data structure matching what the template expects
      // This matches the structure from heats_show endpoint
      const data = {
        event: this.rawData.event,
        judge: this.rawData.judge,
        number: heatNumber,
        style: this.styleValue,
        subjects: hydratedHeats,
        heat: primaryHeat,
        dance: dance.name,  // String for backward compatibility
        scoring: scoring,
        final: final,
        callbacks: callbacks,
        ballrooms: ballrooms,
        ballrooms_count: ballroomsCount,
        // Score lookup objects
        scores: scores,
        value: value,
        good: good,
        bad: bad,
        comments: comments,
        // Navigation
        prev: prev,
        next: next,
        // Additional fields from heats_show
        column_order: event.column_order,
        track_ages: event.track_ages,
        backnums: event.backnums,
        assign_judges: event.assign_judges,
        feedbacks: this.rawData.feedbacks || []
        // TODO: Add these when needed
        // results, combine_open_and_closed, category_scoring_enabled,
        // category_score_assignments, message, etc.
      }

      console.log('Rendering heat with hydrated data')
      const html = this.templates.heat(data)

      // Replace content with rendered heat
      this.element.innerHTML = html

      // Stimulus controllers (score, open-feedback, drop) will auto-attach!
      console.log('Heat rendered successfully')

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
}
