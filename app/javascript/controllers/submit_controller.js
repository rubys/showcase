import { Controller } from "@hotwired/stimulus"
import consumer from 'channels/consumer'
import xterm from 'xterm';

// Connects to data-controller="submit"
export default class extends Controller {
  static targets = ["input", "submit", "output"]

  connect() {
    this.submitTarget.addEventListener('click', event => {
      event.preventDefault()

      const { outputTarget, submitTarget } = this

      const params = {}
      for (const input of this.inputTargets) {
        params[input.name] = input.value
      }

      consumer.subscriptions.create({
        channel: "OutputChannel",
        stream: outputTarget.dataset.stream
      }, {
        connected() {
          if (!outputTarget.parentNode.classList.contains('hidden')) return

          this.perform("command", params)
          submitTarget.disabled=true
          outputTarget.parentNode.classList.remove("hidden")

          this.terminal = new xterm.Terminal()
          this.terminal.open(outputTarget)
        },

        received(data) {
          if (data === "\u0004") {
            this.disconnected()
          } else {
            this.terminal.write(data)
          }
        },

        disconnected() {
          submitTarget.disabled=false
        }
      })
    })
  }
}
