import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "progress", "message", "progressBar" ]
  static values = { userId: Number, database: String, redirectUrl: String, stream: String }

  connect() {
    // Auto-start progress tracking if user ID is set (indicates a progress page after form submission)
    // Check that userId is not just present but also not empty
    if (this.hasUserIdValue && this.userIdValue) {
      this.startProgressTracking()
    }
  }

  startProgressTracking() {
    this.progressTarget.classList.remove("hidden")
    this.updateProgress(0, "Connecting...")

    // Listen for custom JSON events from TurboCable
    this.boundHandleMessage = this.handleMessage.bind(this)
    document.addEventListener('turbo:stream-message', this.boundHandleMessage)
  }

  handleMessage(event) {
    const { stream, data } = event.detail

    // Only handle events for our stream
    if (stream !== this.streamValue) return

    this.handleProgressUpdate(data)
  }

  async triggerUpdate(event) {
    // Show progress indicator immediately
    this.progressTarget.classList.remove("hidden")
    this.updateProgress(0, "Starting...")

    // Disable button
    event.target.disabled = true

    // Listen for progress updates from TurboCable
    this.boundHandleMessage = this.handleMessage.bind(this)
    document.addEventListener('turbo:stream-message', this.boundHandleMessage)

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
  }

  disconnect() {
    if (this.boundHandleMessage) {
      document.removeEventListener('turbo:stream-message', this.boundHandleMessage)
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
