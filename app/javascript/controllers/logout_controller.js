import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="logout"
export default class extends Controller {
  connect() {
    this.element.addEventListener('submit', event => {  
      let credentials = btoa("LOGOUT:PASSWORD");
      var auth = { "Authorization" : `Basic ${credentials}` };
      fetch(window.location, { headers : auth });
      // Note: event.preventDefault(); is *NOT* called
    })
  }
}
