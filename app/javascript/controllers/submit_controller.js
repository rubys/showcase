import { Controller } from "@hotwired/stimulus"
import consumer from 'channels/consumer'
import xterm from '@xterm/xterm';

// Connects to data-controller="submit"
export default class extends Controller {
  static targets = ["input", "submit", "output"]

  connect() {
    this.activeSubscription = null
    this.terminal = null
    
    // Handle multiple submit buttons
    this.submitTargets.forEach(submitTarget => {
      submitTarget.addEventListener('click', event => {
        event.preventDefault()

        // Clean up any existing connection first
        this.cleanup()

        const { outputTarget } = this
        const stream = submitTarget.dataset.stream

        if (!stream) {
          console.error('No stream found for button:', submitTarget.textContent)
          return
        }

        const params = {}
        for (const input of this.inputTargets) {
          params[input.name] = input.value
        }

        // Store the subscription so we can clean it up later
        this.activeSubscription = consumer.subscriptions.create({
          channel: "OutputChannel",
          stream: stream
        }, {
          connected() {
            this.perform("command", params)
            submitTarget.disabled=true
            outputTarget.parentNode.classList.remove("hidden")

            // Clear the output area and create a new terminal
            outputTarget.innerHTML = ''
            this.controller.terminal = new xterm.Terminal()
            this.controller.terminal.open(outputTarget)
          },

          received(data) {
            if (data === "\u0004") {
              this.disconnected()
            } else {
              this.controller.terminal?.write(data)
            }
          },

          disconnected() {
            submitTarget.disabled = false
            // Clean up will be handled by the controller
          }
        })
        
        // Store reference to controller in subscription for access in callbacks
        this.activeSubscription.controller = this
      })
    })
  }
  
  cleanup() {
    // Clean up existing subscription
    if (this.activeSubscription) {
      this.activeSubscription.unsubscribe()
      this.activeSubscription = null
    }
    
    // Clean up existing terminal
    if (this.terminal) {
      this.terminal.dispose()
      this.terminal = null
    }
    
    // Clear output area
    if (this.hasOutputTarget) {
      this.outputTarget.innerHTML = ''
    }
  }
  
  disconnect() {
    this.cleanup()
  }
}
