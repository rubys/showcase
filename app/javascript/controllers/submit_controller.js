import { Controller } from "@hotwired/stimulus"
import consumer from 'channels/consumer'
import xterm from '@xterm/xterm';

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
      submitTarget.addEventListener('click', async (event) => {
        event.preventDefault()

        // Clean up any existing connection first
        this.cleanup()

        const { outputTarget } = this
        const commandType = submitTarget.dataset.commandType

        if (!commandType) {
          console.error('No command type found for button:', submitTarget.textContent)
          return
        }

        submitTarget.disabled = true

        // Collect parameters
        const params = {}
        for (const input of this.inputTargets) {
          params[input.name] = input.value
        }

        try {
          // POST to start job
          const response = await fetch(`/event/execute_command/${commandType}`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
            },
            body: JSON.stringify({ params })
          })

          if (!response.ok) {
            throw new Error(`HTTP ${response.status}`)
          }

          const { stream } = await response.json()

          // Parse stream name to get components
          const match = stream.match(/command_output_(.+)_(\d+)_(.+)/)
          if (!match) {
            throw new Error('Invalid stream format')
          }

          const [, database, userId, jobId] = match

          // Subscribe to output stream
          this.activeSubscription = consumer.subscriptions.create({
            channel: "CommandOutputChannel",
            database: database,
            user_id: userId,
            job_id: jobId
          }, {
            connected() {
              outputTarget.parentNode.classList.remove("hidden")
              outputTarget.innerHTML = ''
              this.controller.terminal = new xterm.Terminal()
              this.controller.terminal.open(outputTarget)
            },

            received(data) {
              if (data === "\u0004") {
                // Completion marker
                this.disconnected()
              } else {
                this.controller.terminal?.write(data)
              }
            },

            disconnected() {
              submitTarget.disabled = false
            }
          })

          this.activeSubscription.controller = this

        } catch (error) {
          console.error('Failed to start command:', error)
          submitTarget.disabled = false
          alert(`Failed to start command: ${error.message}`)
        }
      })
    })
  }
  
  cleanup() {
    // Clean up existing subscription
    if (this.activeSubscription) {
      this.activeSubscription.unsubscribe()
      this.activeSubscription = null
    }
    
    // More aggressive cleanup - unsubscribe from all CommandOutputChannel subscriptions
    // This helps with stale connections in production
    if (consumer && consumer.subscriptions) {
      const commandSubscriptions = consumer.subscriptions.subscriptions.filter(
        subscription => subscription.identifier &&
          JSON.parse(subscription.identifier).channel === 'CommandOutputChannel'
      )
      commandSubscriptions.forEach(subscription => {
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
