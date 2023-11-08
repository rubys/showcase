import { Controller } from "@hotwired/stimulus"
import consumer from 'channels/consumer'
import xterm from 'xterm';

// Connects to data-controller="submit"
export default class extends Controller {
  static targets = ["input", "submit", "output"]

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

          this.terminal = new xterm.Terminal()
          this.terminal.open(outputTarget)
        },

        received(data) {
          this.terminal.write(data)
        }
      })
    })
  }
}
