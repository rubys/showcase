import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [ "progress", "message", "progressBar", "form" ]
  static values = { userId: Number, database: String, redirectUrl: String }

  connect() {
    this.consumer = createConsumer()
    this.subscription = null
  }

  submitViaButton(event) {
    // Programmatically trigger form submit when button is clicked
    if (this.hasFormTarget) {
      const submitEvent = new Event('submit', { bubbles: true, cancelable: true })
      this.formTarget.dispatchEvent(submitEvent)
    }
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

    // Show progress indicator immediately
    this.progressTarget.classList.remove("hidden")
    this.updateProgress(0, "Connecting...")

    // Disable form
    if (this.hasFormTarget) {
      this.formTarget.querySelectorAll('input, button').forEach(el => {
        el.disabled = true
      })
    }

    // Subscribe to progress updates BEFORE submitting
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: "ConfigUpdateChannel",
        user_id: this.userIdValue,
        database: this.databaseValue
      },
      {
        connected: () => {
          console.log("WebSocket connected, now submitting form")
          this.updateProgress(0, "Submitting...")
          this.submitForm(event.target)
        },
        received: (data) => {
          this.handleProgressUpdate(data)
        }
      }
    )
  }

  async submitForm(form) {
    try {
      const formData = new FormData(form)

      // Rails uses a hidden _method field for PATCH/PUT/DELETE
      // Extract the actual method from the form data
      const method = formData.get('_method') || form.method || 'POST'

      // Remove _method from FormData since we're using it as the actual HTTP method
      formData.delete('_method')

      // Convert FormData to URLSearchParams for non-multipart encoding
      // This allows PATCH/PUT/DELETE to work properly
      const params = new URLSearchParams()
      for (const [key, value] of formData.entries()) {
        if (value instanceof File) {
          // Skip file uploads for now
          continue
        }
        params.append(key, value)
      }

      const response = await fetch(form.action, {
        method: method.toUpperCase(),
        body: params,
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Content-Type": "application/x-www-form-urlencoded"
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
