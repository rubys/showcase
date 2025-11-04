import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "button", "progress", "message", "progressBar" ]
  static values = { cleanupUrl: String, stream: String, requestId: String }

  connect() {
    this.filename = null
    // Listen for custom JSON events from TurboCable
    this.boundHandleMessage = this.handleMessage.bind(this)
    document.addEventListener('turbo:stream-message', this.boundHandleMessage)
  }

  async disconnect() {
    document.removeEventListener('turbo:stream-message', this.boundHandleMessage)

    // Clean up the generated file when leaving the page
    if (this.filename && this.hasCleanupUrlValue) {
      try {
        await fetch(this.cleanupUrlValue, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
          },
          body: JSON.stringify({ filename: this.filename })
        })
      } catch (error) {
        // Silently fail - page is unloading anyway
      }
    }
  }

  handleMessage(event) {
    const { stream, data } = event.detail

    // Only handle events for our stream
    if (stream !== this.streamValue) return

    // Handle different message types
    this.handleProgressUpdate(data)
  }
  
  async generate() {
    this.buttonTarget.disabled = true
    this.buttonTarget.classList.add("opacity-50", "cursor-not-allowed")
    this.progressTarget.classList.remove("hidden")

    try {
      const response = await fetch(window.location.pathname + `.json?request_id=${this.requestIdValue}`, {
        method: "GET",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      // Job will broadcast updates via TurboCable
      // No need to create subscription - we're already listening via turbo:stream-message
    } catch (error) {
      console.error("Error initiating playlist generation:", error)
      this.messageTarget.textContent = "Failed to start playlist generation"
      this.messageTarget.classList.add("text-red-600")
      this.resetButton()
    }
  }
  
  handleProgressUpdate(data) {
    if (data.status === "processing") {
      this.updateProgress(data.progress || 0, data.message || "Processing...")
    } else if (data.status === "completed") {
      this.updateProgress(100, "Download ready!")
      this.showDownloadLink(data.download_key)
    } else if (data.status === "error") {
      this.messageTarget.textContent = data.message || "An error occurred"
      this.messageTarget.classList.add("text-red-600")
      this.resetButton()
    }
  }
  
  updateProgress(percent, message) {
    // Make sure the progress bar container is visible
    this.progressBarTarget.parentElement.classList.remove("hidden")
    this.progressBarTarget.style.width = `${percent}%`
    this.progressBarTarget.textContent = `${percent}%`
    this.messageTarget.textContent = message
  }
  
  showDownloadLink(filename) {
    const downloadUrl = `${window.location.pathname}.zip?filename=${filename}`

    // Store the filename for cleanup on disconnect (though cleanup is now automatic via 2-hour expiry)
    this.filename = filename
    
    // Hide only the progress bar (not the whole container)
    this.progressBarTarget.parentElement.classList.add("hidden")
    this.resetButton()
    
    // Create and show a proper download link (stays visible after clicking)
    this.messageTarget.innerHTML = `
      <a href="${downloadUrl}" 
         class="inline-flex items-center px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 font-medium"
         download>
        <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
        </svg>
        Download DJ Playlist
      </a>
    `
  }
  
  resetButton() {
    this.buttonTarget.disabled = false
    this.buttonTarget.classList.remove("opacity-50", "cursor-not-allowed")
  }
}
