import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="anchored"
// see https://github.com/hotwired/turbo/issues/211
// use with data-turbo=false on form elements
export default class extends Controller {
  connect() {
    let id = window.location.hash;
    if (id.length > 1) {
      let element = document.getElementById(id.slice(1));
      if (element) element.scrollIntoView(true);
    }
  }
}