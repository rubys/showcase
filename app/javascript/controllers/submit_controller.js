import { Controller } from "@hotwired/stimulus"
import consumer from 'channels/consumer'

// Connects to data-controller="submit"
export default class extends Controller {
  static targets = [ "input", "submit", "output" ]

  connect() {
    this.submitTarget.addEventListener('click', event => {
      event.preventDefault()

      const { outputTarget } = this

      const params = {}
      for (const input of this.inputTargets) {
        params[input.name] = input.value
      }

      consumer.subscriptions.create({
        channel: "OutputChannel",
        stream: outputTarget.dataset.stream
      }, {
        connected() {
          this.perform("command", params)
          outputTarget.parentNode.classList.remove("hidden")
        },

        received(data) {
          let div = document.createElement("div")
          div.setAttribute("class", "pb-2 break-all overflow-x-hidden")
          div.innerHTML = data
          let bottom = outputTarget.scrollHeight - outputTarget.scrollTop - outputTarget.clientHeight
          outputTarget.appendChild(div)
          if (bottom == 0) div.scrollIntoView()
        }
      })
    })
  }
}
