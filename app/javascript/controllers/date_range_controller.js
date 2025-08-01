import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="date-range"
export default class extends Controller {
  static targets = ["output", "startDate", "endDate"]
  static values = { date: String, year: String }

  connect() {
    if (this.hasDateValue && this.dateValue.match(/^\d{4}-\d{2}-\d{2}( - \d{4}-\d{2}-\d{2})?$/)) {
      this.outputTarget.textContent = this.formatDate(this.dateValue.split(' - '))
    }

    // Set up date synchronization using targets
    if (this.hasStartDateTarget && this.hasEndDateTarget) {
      this.startDateTarget.addEventListener('change', () => {
        if (this.startDateTarget.value > this.endDateTarget.value) {
          this.endDateTarget.value = this.startDateTarget.value
        }
      })
      this.endDateTarget.addEventListener('change', () => {
        if (this.endDateTarget.value < this.startDateTarget.value) {
          this.startDateTarget.value = this.endDateTarget.value
        }
      })
    }

    let formatter = new Intl.DateTimeFormat(document.body.dataset.locale, {
      hour: 'numeric',
      minute: 'numeric'
    })

    this.element.querySelectorAll('td[data-start][data-finish]').forEach(cell => {
      const start = new Date(Date.parse(cell.dataset.start))
      const finish = new Date(Date.parse(cell.dataset.finish))
      cell.textContent = formatter.formatRange(start, finish).toLowerCase().replaceAll(/ /g, '\u00A0');
    })

    const direction = this.element.querySelector('#avail_direction')
    if (direction) {
      direction.addEventListener('change', () => this.update_avail_direction())
      this.update_avail_direction()
    }

    formatter = new Intl.DateTimeFormat(document.body.dataset.locale, {
      weekday: 'long'
    })

    for (let option of this.element.querySelectorAll('#avail_date option' )) {
      option.textContent = formatter.format(new Date(option.value))
    }

    for (let option of this.element.querySelectorAll('#category_day option' )) {
      if (option.value == "") continue
      const time = new Date(option.value + "T12:00:00Z")
      option.textContent = formatter.format(time)
    }
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

  update_avail_direction() {
    const direction = this.element.querySelector('#avail_direction')
    if (!direction) return
    const date = this.element.querySelector('#avail_date')
    const time = this.element.querySelector('#avail_time')

    if (direction.value === '*') {
      direction.classList.add("col-span-3")
      date.classList.add("hidden")
      time.classList.add("hidden")
    } else {
      direction.classList.remove("col-span-3")
      date.classList.remove("hidden")
      time.classList.remove("hidden")

      if (date.querySelectorAll("option").length === 1) {
        date.classList.add("hidden")
      } else {
        date.classList.remove("hidden")
        time.classList.remove("col-span-2")
      }
    }
  }
} 