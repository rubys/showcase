import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="geocode"
export default class extends Controller {
  static targets = ["name", "latitude", "longitude", "locale"]

  connect() {
    this.nameTarget.addEventListener('change', () => {
      if (this.latitudeTarget.value || this.longitudeTarget.value) return
      let name = this.nameTarget.value

      fetch(`https://nominatim.openstreetmap.org/search?format=jsonv2&q=${encodeURIComponent(name)}`, {
        headers: {
          'User-Agent': 'Showcase'
        }
      })
        .then(response => response.json())
        .then(locations => {
          let location = locations[0]
          if (!location) return 
          this.element.title = location.display_name
          this.latitudeTarget.value = location.lat
          this.longitudeTarget.value = location.lon
          this.updateLocale()

          this.nameTarget.parentElement.querySelector('label').title =location.display_name
        })
    })

    this.latitudeTarget.addEventListener('change', () => {
      this.updateLocale()
    })

    this.longitudeTarget.addEventListener('change', () => {
      this.updateLocale()
    })
  }

  updateLocale() {
    let locale = this.element.dataset.locale
    let latitude = this.latitudeTarget.value
    let longitude = this.longitudeTarget.value
    fetch(`${locale}?lat=${latitude}&lng=${longitude}`).then(response => {
      response.json().then(json => {
        this.localeTarget.value = json.locale
      })
    })
  }
}