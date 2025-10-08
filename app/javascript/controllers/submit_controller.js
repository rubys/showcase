import { Controller } from "@hotwired/stimulus"
import consumer from 'channels/consumer'
import * as xterm from '@xterm/xterm';

// Connects to data-controller="submit"
export default class extends Controller {
  static targets = ["input", "submit", "output"]

  connect() {
    this.activeSubscription = null
    this.terminal = null
    
    // Clean up any existing subscriptions when connecting
    this.cleanup()
    
    // Add cleanup on page unload to prevent stale connections
    this.handlePageUnload = () => {
      this.cleanup()
    }
    window.addEventListener('beforeunload', this.handlePageUnload)
    window.addEventListener('pagehide', this.handlePageUnload)
    
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
            // Add a small delay to ensure WebSocket is fully ready
            setTimeout(() => {
              this.perform("command", params)
              submitTarget.disabled=true
              outputTarget.parentNode.classList.remove("hidden")

              // Clear the output area and create a new terminal
              outputTarget.innerHTML = ''
              this.controller.terminal = new xterm.Terminal()
              this.controller.terminal.open(outputTarget)
            }, 100)
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
    
    // More aggressive cleanup - unsubscribe from all OutputChannel subscriptions
    // This helps with stale connections in production
    if (consumer && consumer.subscriptions) {
      const outputChannelSubscriptions = consumer.subscriptions.subscriptions.filter(
        subscription => subscription.identifier && JSON.parse(subscription.identifier).channel === 'OutputChannel'
      )
      outputChannelSubscriptions.forEach(subscription => {
        subscription.unsubscribe()
      })
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
    
    // Remove page unload event listeners
    if (this.handlePageUnload) {
      window.removeEventListener('beforeunload', this.handlePageUnload)
      window.removeEventListener('pagehide', this.handlePageUnload)
    }
  }
}
