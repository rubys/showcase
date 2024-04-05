import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="copy-entries"
export default class extends Controller {
  connect() {
    this.open_entries = document.getElementById('sect-open')
    this.closed_entries = document.getElementById('sect-closed')
    this.copy_from_closed = document.getElementById('copy-from-closed')

    if (!this.open_entries || !this.closed_entries || !this.copy_from_closed) return

    this.copy_from_closed.addEventListener('click', event => {
      event.preventDefault()
      
      this.closed_entries.querySelectorAll('input').forEach(input => {
        if (!input.id) return
  
        const open_id = input.id.replace('[Closed]', '[Open]')
        const open_input = document.getElementById(open_id)
        const clone = input.cloneNode(true)
        clone.id = open_id
        clone.name = input.name.replace('[Closed]', '[Open]')
        clone.addEventListener('change', this.hideShowButton)
        open_input.replaceWith(clone)
      })

      this.hideShowButton()
    })

    this.closed_entries.querySelectorAll('input').forEach(input => {
      if (input.id) input.addEventListener('change', this.hideShowButton)
    })

    this.open_entries.querySelectorAll('input').forEach(input => {
      if (input.id) input.addEventListener('change', this.hideShowButton)
    })

    this.hideShowButton()
  }

  hideShowButton = () => {
    console.log('hideShowButton')
    if (this.anyChecked(this.closed_entries) && !this.anyChecked(this.open_entries)) {
      this.copy_from_closed.classList.remove('hidden')
    } else {
      this.copy_from_closed.classList.add('hidden')
    }
  }

  anyChecked = element => {
    return [...element.querySelectorAll('input')].some(input => input.type == 'checkbox' ? input.checked : input.value > 0)
  }
}
