import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="progressive-audio"
export default class extends Controller {
  static targets = ["button", "progress", "progressBar", "message"]

  async cache() {
    // Disable button and show progress
    this.buttonTarget.disabled = true
    this.progressTarget.classList.remove("hidden")

    // Find all audio elements on the page
    const audioElements = document.querySelectorAll("audio[controls]")
    const total = audioElements.length
    let completed = 0
    let failed = 0

    // Update progress
    const updateProgress = () => {
      const percent = Math.round((completed / total) * 100)
      this.progressBarTarget.style.width = `${percent}%`
      this.progressBarTarget.textContent = `${percent}%`

      if (failed > 0) {
        this.messageTarget.textContent = `Cached ${completed} of ${total} songs (${failed} failed)`
      } else {
        this.messageTarget.textContent = `Cached ${completed} of ${total} songs`
      }
    }

    this.messageTarget.textContent = `Caching ${total} songs...`

    // Process each audio element
    for (const audio of audioElements) {
      const source = audio.querySelector("source")
      if (!source) {
        completed++
        updateProgress()
        continue
      }

      const url = source.src

      // Skip if already a data URL
      if (url.startsWith("data:")) {
        completed++
        updateProgress()
        continue
      }

      try {
        // Fetch the audio file
        const response = await fetch(url)
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`)
        }

        const blob = await response.blob()

        // Convert to data URL
        const dataUrl = await this.blobToDataURL(blob)

        // Replace the source
        source.src = dataUrl

        // Force reload
        audio.load()

        completed++
        updateProgress()
      } catch (error) {
        console.error(`Failed to cache audio from ${url}:`, error)
        failed++
        completed++
        updateProgress()
      }
    }

    // Final message
    if (failed > 0) {
      this.messageTarget.textContent = `Completed: ${completed - failed} songs cached, ${failed} failed`
      this.progressBarTarget.classList.add("bg-yellow-500")
      this.progressBarTarget.classList.remove("bg-blue-500")
    } else {
      this.messageTarget.textContent = `All ${total} songs cached successfully!`
      this.progressBarTarget.classList.add("bg-green-500")
      this.progressBarTarget.classList.remove("bg-blue-500")
    }
  }

  // Helper method to convert blob to data URL
  blobToDataURL(blob) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = () => resolve(reader.result)
      reader.onerror = reject
      reader.readAsDataURL(blob)
    })
  }
}
