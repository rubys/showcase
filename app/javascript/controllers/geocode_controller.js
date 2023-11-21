import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="geocode"
export default class extends Controller {
  static targets = ["name", "latitude", "longitude", "token"]

  connect() {
    this.nameTarget.addEventListener('change', () => {
      let name = this.nameTarget.value

      if (!this.tokenTarget.value) {
        this.tokenTarget.value = name.toLowerCase().replace(/\W+/g, '')
      }

      fetch(`https://geocode.maps.co/search?q=${encodeURIComponent(name)}`)
        .then(response => response.json())
        .then(locations => {
          let location = locations[0]
          if (!location) return 
          this.latitudeTarget.value = location.lat
          this.longitudeTarget.value = location.lon

          this.nameTarget.parentElement.querySelector('label').title =
            location.display_name
        })
    })
  }
}
