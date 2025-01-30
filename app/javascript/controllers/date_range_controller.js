import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="date-range"
export default class extends Controller {
  static targets = ["output"]
  static values = { date: String, year: String }

  connect() {
    if (this.hasDateValue && this.dateValue.match(/^\d{4}-\d{2}-\d{2}( - \d{4}-\d{2}-\d{2})?$/)) {
      this.outputTarget.textContent = this.formatDate(this.dateValue.split(' - '))
    }

    const startDate = this.element.querySelector('#event_start_date')
    if (startDate) {
      const endDate = this.element.querySelector('#event_end_date')
      startDate.addEventListener('change', () => {
        if (startDate.value > endDate.value) endDate.value = startDate.value
      })
      endDate.addEventListener('change', () => {
        if (endDate.value < startDate.value) startDate.value = endDate.value
      })
    }

    const formatter = new Intl.DateTimeFormat(document.body.dataset.locale, {
      hour: 'numeric',
      minute: 'numeric'
    })

    this.element.querySelectorAll('td[data-start][data-finish]').forEach(cell => {
      const start = new Date(Date.parse(cell.dataset.start))
      const finish = new Date(Date.parse(cell.dataset.finish))
      cell.textContent = formatter.formatRange(start, finish).replaceAll(/ /g, '\u00A0');
    })
  }

  formatDate(dateValues) {
    try {
      const dates = dateValues.map(dateValue => new Date(dateValue + 'T12:00:00Z'))
      
      // Check if dates are valid
      if (dates.some(date => isNaN(date.getTime()))) {
        return dateValues.join(' - ')
      }

      const formatter = new Intl.DateTimeFormat(document.body.dataset.locale, {
        weekday: (dates.length === 1) ? 'long' : undefined,
        year: this.yearValue === dates[0].getFullYear().toString() ? undefined : 'numeric',
        month: 'long',
        day: 'numeric'
      })

      if (dates.length === 1) {
        return formatter.format(dates[0])
      } else {
        return formatter.formatRange(dates[0], dates[1])
      }
    } catch (e) {
      // Fallback to original date string if there's any error
      return dateValues.join(' - ')
    }
  }
} 