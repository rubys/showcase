import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="mapper"
export default class extends Controller {
  connect() {
    let dots = [...this.element.querySelectorAll('svg a')]
    let machines = this.element.querySelectorAll('tbody tr td:first-child a')
    let studios = this.element.querySelectorAll('tbody tr td:last-child a')

    function findDot(href) {
      return dots.find(dot => dot.href.baseVal == href)
    }

    for (let studio of studios) {
      studio.addEventListener('mouseover', () => {
        studio.style.color = "red"
        let dot = findDot(studio.getAttribute('href'))
        if (dot) {
          dot.parentElement.appendChild(dot)
          dot.firstElementChild.style.fill = "red"
        }

        let region = studio.closest('tr').querySelector('td a')
        region.style.color = "green"
        dot = findDot(region.getAttribute('href'))
        if (dot) {
          dot.firstElementChild.style.fill = "green"
        }
      })

      studio.addEventListener('mouseleave', () => {
        studio.style.color = ""
        let dot = findDot(studio.getAttribute('href'))
        if (dot) {
          dot.firstElementChild.style.fill = ""
        }

        let region = studio.closest('tr').querySelector('td a')
        region.style.color = ""
        dot = findDot(region.getAttribute('href'))
        if (dot) {
          dot.firstElementChild.style.fill = ""
        }
      })
    }

    for (let machine of machines) {
      machine.addEventListener('mouseover', () => {
        machine.style.color = "red"
        let dot = findDot(machine.getAttribute('href'))
        if (dot) {
          dot.firstElementChild.style.fill = "red"
          dot.firstElementChild.style.opacity = "0.5"
        }

        let studios = machine.closest('tr').querySelectorAll('td:last-child a')
        for (let studio of studios) {
          studio.style.color = "green"
          dot = findDot(studio.getAttribute('href'))
          if (dot) {
            dot.firstElementChild.style.fill = "green"
          }
        }
      })

      machine.addEventListener('mouseleave', () => {
        machine.style.color = ""
        let dot = findDot(machine.getAttribute('href'))
        if (dot) {
          dot.parentElement.appendChild(dot)
          dot.firstElementChild.style.fill = ""
        }

        let studios = machine.closest('tr').querySelectorAll('td:last-child a')
        for (let studio of studios) {
          studio.style.color = ""
          dot = findDot(studio.getAttribute('href'))
          if (dot) {
            dot.firstElementChild.style.fill = ""
          }
        }
      })
    }

    for (let dot of dots) {
      dot.addEventListener('mouseover', event => {
        let link = this.element.querySelector(`tbody a[href="${dot.href.baseVal}"]`)
        event = new event.constructor(event.type, event)
        if (link) link.dispatchEvent(event)
      })

      dot.addEventListener('mouseleave', event => {
        let link = this.element.querySelector(`tbody a[href="${dot.href.baseVal}"]`)
        event = new event.constructor(event.type, event)
        if (link) link.dispatchEvent(event)
      })
    }
  }
}
