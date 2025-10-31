import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [ "progress", "message", "progressBar" ]
  static values = { userId: Number, database: String, redirectUrl: String }

  connect() {
    this.consumer = createConsumer()
    this.subscription = null

    // Auto-start progress tracking if user ID is set (indicates a progress page after form submission)
    // Check that userId is not just present but also not empty
    if (this.hasUserIdValue && this.userIdValue) {
      this.startProgressTracking()
    }
  }

  startProgressTracking() {
    this.progressTarget.classList.remove("hidden")
    this.updateProgress(0, "Connecting...")

    this.subscription = this.consumer.subscriptions.create(
      {
        channel: "ConfigUpdateChannel",
        user_id: this.userIdValue,
        database: this.databaseValue
      },
      {
        connected: () => {
          this.updateProgress(0, "Starting...")
        },
        received: (data) => {
          this.handleProgressUpdate(data)
        }
      }
    )
  }

  async triggerUpdate(event) {
    // Show progress indicator immediately
    this.progressTarget.classList.remove("hidden")
    this.updateProgress(0, "Connecting...")

    // Disable button
    event.target.disabled = true

    // Subscribe to progress updates BEFORE triggering the job
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: "ConfigUpdateChannel",
        user_id: this.userIdValue,
        database: this.databaseValue
      },
      {
        connected: async () => {
          this.updateProgress(0, "Triggering update...")

          // Trigger the ConfigUpdateJob
          try {
            // Use relative path which will include RAILS_RELATIVE_URL_ROOT automatically
            const response = await fetch(window.location.pathname.replace('/apply', '/trigger_config_update'), {
              method: 'POST',
              headers: {
                "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
              }
            })

            if (!response.ok) {
              throw new Error(`HTTP error! status: ${response.status}`)
            }
          } catch (error) {
            console.error("Error triggering update:", error)
            this.messageTarget.textContent = "Failed to start update"
            this.messageTarget.classList.add("text-red-600")
            event.target.disabled = false
          }
        },
        received: (data) => {
          this.handleProgressUpdate(data)
        }
      }
    )
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
  }

  handleProgressUpdate(data) {
    if (data.status === "processing") {
      this.updateProgress(data.progress || 0, data.message || "Processing...")
    } else if (data.status === "completed") {
      this.updateProgress(100, data.message || "Complete!")

      // Auto-redirect after a brief delay
      setTimeout(() => {
        if (this.hasRedirectUrlValue && this.redirectUrlValue) {
          window.location.href = this.redirectUrlValue
        }
      }, 1000)
    } else if (data.status === "error") {
      this.messageTarget.textContent = data.message || "An error occurred"
      this.messageTarget.classList.add("text-red-600")
    }
  }

  updateProgress(percent, message) {
    this.progressBarTarget.style.width = `${percent}%`
    this.progressBarTarget.textContent = `${percent}%`
    this.messageTarget.textContent = message
    this.messageTarget.classList.remove("text-red-600")
  }
}
