import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [ "progress", "message", "progressBar", "form" ]
  static values = { userId: Number, database: String, redirectUrl: String }

  connect() {
    this.consumer = createConsumer()
    this.subscription = null
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
  }

  async submit(event) {
    event.preventDefault()

    // Show progress indicator
    this.progressTarget.classList.remove("hidden")

    // Disable form
    if (this.hasFormTarget) {
      this.formTarget.querySelectorAll('input, button').forEach(el => {
        el.disabled = true
      })
    }

    // Subscribe to progress updates
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: "ConfigUpdateChannel",
        user_id: this.userIdValue,
        database: this.databaseValue
      },
      {
        received: (data) => {
          this.handleProgressUpdate(data)
        }
      }
    )

    // Submit the form
    try {
      const formData = new FormData(event.target)
      const response = await fetch(event.target.action, {
        method: event.target.method,
        body: formData,
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
    } catch (error) {
      console.error("Error submitting form:", error)
      this.messageTarget.textContent = "Failed to submit form"
      this.messageTarget.classList.add("text-red-600")
      this.resetForm()
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
      this.resetForm()
    }
  }

  updateProgress(percent, message) {
    this.progressBarTarget.style.width = `${percent}%`
    this.progressBarTarget.textContent = `${percent}%`
    this.messageTarget.textContent = message
    this.messageTarget.classList.remove("text-red-600")
  }

  resetForm() {
    if (this.hasFormTarget) {
      this.formTarget.querySelectorAll('input, button').forEach(el => {
        el.disabled = false
      })
    }
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }
}
