import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "progress", "message", "progressBar", "form", "redirectUrl" ]
  static values = {
    userId: Number,
    database: String,
    redirectUrl: String,
    stream: String,
    formId: String,
    submitUrl: String
  }

  connect() {
    // Start listening for progress updates immediately when page loads
    // This ensures WebSocket is connected before any form submission
    this.boundHandleMessage = this.handleMessage.bind(this)
    document.addEventListener('turbo:stream-message', this.boundHandleMessage)
  }

  handleMessage(event) {
    const { stream, data } = event.detail

    // Only handle events for our stream
    if (stream !== this.streamValue) return

    this.handleProgressUpdate(data)
  }

  // Intercept form submission to use fetch + Turbo Stream
  async submitForm(event) {
    const form = event.target
    const submitter = event.submitter

    // If the submitter has data-skip-turbo-stream, let the form submit normally
    if (submitter && submitter.dataset.skipTurboStream) {
      return // Don't prevent default, let form submit normally
    }

    event.preventDefault()

    const formData = new FormData(form)
    const submitButton = submitter || form.querySelector('[type="submit"]')

    // Disable submit button
    if (submitButton) {
      submitButton.disabled = true
    }

    try {
      const response = await fetch(form.action, {
        method: form.method || 'POST',
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: formData
      })

      if (response.ok) {
        // Process the Turbo Stream response
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      } else if (response.status === 422) {
        // Validation errors - render the Turbo Stream with errors
        const html = await response.text()
        Turbo.renderStreamMessage(html)
        // Re-enable button for retry
        if (submitButton) {
          submitButton.disabled = false
        }
      } else {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
    } catch (error) {
      console.error("Error submitting form:", error)
      alert("Failed to submit form. Please try again.")
      if (submitButton) {
        submitButton.disabled = false
      }
    }
  }

  async triggerUpdate(event) {
    // Show progress indicator immediately
    this.progressTarget.classList.remove("hidden")
    this.updateProgress(0, "Starting...")

    // Disable button
    event.target.disabled = true

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
        // Check for redirect URL from target element first (set by Turbo Stream partial),
        // then fall back to data attribute value (set on initial page load)
        const redirectUrl = this.hasRedirectUrlTarget
          ? this.redirectUrlTarget.dataset.url
          : this.redirectUrlValue

        if (redirectUrl) {
          window.location.href = redirectUrl
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
