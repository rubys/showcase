import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [ "button", "progress", "message", "progressBar" ]
  static values = { cleanupUrl: String }

  connect() {
    this.consumer = createConsumer()
    this.cacheKey = null
  }
  
  async disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
    // Clean up the cache when leaving the page
    if (this.cacheKey && this.hasCleanupUrlValue) {
      try {
        await fetch(this.cleanupUrlValue, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
          },
          body: JSON.stringify({ cache_key: this.cacheKey })
        })
      } catch (error) {
        // Silently fail - page is unloading anyway
      }
    }
  }
  
  async generate() {
    this.buttonTarget.disabled = true
    this.buttonTarget.classList.add("opacity-50", "cursor-not-allowed")
    this.progressTarget.classList.remove("hidden")
    
    try {
      const response = await fetch(window.location.pathname + ".json", {
        method: "GET",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })
      
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      
      const data = await response.json()

      this.subscription = this.consumer.subscriptions.create(
        { channel: "OfflinePlaylistChannel", user_id: data.user_id, database: data.database },
        {
          received: (data) => {
            this.handleProgressUpdate(data)
          }
        }
      )
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
  
  showDownloadLink(cacheKey) {
    const downloadUrl = `${window.location.pathname}.zip?cache_key=${cacheKey}`
    
    // Store the cache key for cleanup on disconnect
    this.cacheKey = cacheKey
    
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
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }
}
