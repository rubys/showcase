import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [ "progress", "message", "progressBar", "form" ]
  static values = { userId: Number, database: String, redirectUrl: String }

  connect() {
    this.consumer = createConsumer()
    this.subscription = null

    // Auto-start progress tracking if this is a progress page (not a form page)
    if (!this.hasFormTarget && this.hasUserIdValue) {
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

    // Capture form data BEFORE disabling inputs (disabled inputs aren't included in FormData!)
    const form = event.target
    const formData = new FormData(form)

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
          this.updateProgress(0, "Submitting...")
          this.submitForm(form, formData)
        },
        received: (data) => {
          this.handleProgressUpdate(data)
        }
      }
    )
  }

  async submitForm(form, formData) {
    try {
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
        if (response.status === 422) {
          // Validation error - get the HTML response and update the page
          const html = await response.text()
          const parser = new DOMParser()
          const doc = parser.parseFromString(html, 'text/html')

          // Extract the form with errors from the response
          const newForm = doc.querySelector('#user-form')
          if (newForm && this.hasFormTarget) {
            // Replace the current form with the one containing error messages
            this.formTarget.outerHTML = newForm.outerHTML
          }

          // Hide progress bar and unsubscribe
          this.progressTarget.classList.add("hidden")
          if (this.subscription) {
            this.subscription.unsubscribe()
            this.subscription = null
          }
        } else {
          throw new Error(`HTTP error! status: ${response.status}`)
        }
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
