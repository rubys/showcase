import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="progressive-audio"
export default class extends Controller {
  static targets = ["button", "progress", "progressBar", "message", "stats", "clearButton"]
  static values = { eventId: String }

  async connect() {
    const totalStart = performance.now()

    // Initialize IndexedDB
    const initStart = performance.now()
    this.db = await this.initDB()
    console.debug(`[Cache] IndexedDB init: ${(performance.now() - initStart).toFixed(0)}ms`)

    // Cleanup expired songs
    const cleanupStart = performance.now()
    await this.cleanupExpired()
    console.debug(`[Cache] Cleanup expired: ${(performance.now() - cleanupStart).toFixed(0)}ms`)

    // Auto-restore cached songs
    const restoreStart = performance.now()
    await this.restoreCachedSongs()
    console.debug(`[Cache] Restore cached songs: ${(performance.now() - restoreStart).toFixed(0)}ms`)

    // Update cache statistics
    const statsStart = performance.now()
    await this.updateCacheStats()
    console.debug(`[Cache] Update stats: ${(performance.now() - statsStart).toFixed(0)}ms`)

    console.debug(`[Cache] Total page load time: ${(performance.now() - totalStart).toFixed(0)}ms`)
  }

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
    const updateProgress = (currentSong = null) => {
      const percent = Math.round((completed / total) * 100)
      this.progressBarTarget.style.width = `${percent}%`
      this.progressBarTarget.textContent = `${percent}%`

      let message = `Cached ${completed} of ${total} songs`
      if (failed > 0) {
        message += ` (${failed} failed)`
      }
      if (currentSong) {
        message += ` - ${currentSong}`
      }
      this.messageTarget.textContent = message
    }

    this.messageTarget.textContent = `Caching ${total} songs...`

    // Process each audio element sequentially
    for (let i = 0; i < audioElements.length; i++) {
      const audio = audioElements[i]
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

      // Get song info from the row
      const row = audio.closest("tr")
      const heatNumber = row?.querySelector("td:first-child")?.textContent?.trim() || `${i + 1}`
      const songInfo = `Heat ${heatNumber}`

      updateProgress(songInfo)

      // Check IndexedDB first
      const cached = await this.getCachedSong(url)
      if (cached) {
        // Already cached - use it
        source.src = URL.createObjectURL(cached.blob)
        audio.load()
        row.classList.add('cached')
        completed++
        updateProgress()
        continue
      }

      try {
        // Download with retry logic
        const blob = await this.downloadWithRetry(url, source.type, 3)

        // Store in IndexedDB
        await this.storeSong(url, blob, source.type)

        // Create Object URL
        source.src = URL.createObjectURL(blob)

        // Force reload
        audio.load()

        // Mark as cached
        row.classList.add('cached')

        completed++
        updateProgress()
      } catch (error) {
        console.error(`Failed to cache audio from ${url} after retries:`, error)
        failed++
        completed++
        updateProgress()
      }
    }

    // Update cache stats after caching
    await this.updateCacheStats()

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

  // Download with retry logic and progressive fallback strategies
  async downloadWithRetry(url, contentType, maxRetries = 3) {
    let lastError = null
    let supportsRanges = null

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Wait before retry (exponential backoff: 1s, 2s, 4s)
        if (attempt > 0) {
          const delay = Math.pow(2, attempt - 1) * 1000
          await new Promise(resolve => setTimeout(resolve, delay))
        }

        // Progressive fallback strategy:
        // 1st attempt: Simple fetch (fastest if it works)
        // 2nd attempt: Chunked streaming (better timeout detection)
        // 3rd+ attempt: Range requests if supported (bypasses size limits)

        if (attempt === 0) {
          console.debug(`Attempt ${attempt + 1}: Simple fetch for ${url}`)
          return await this.downloadSimple(url, contentType)
        } else if (attempt === 1) {
          console.debug(`Attempt ${attempt + 1}: Chunked streaming for ${url}`)
          return await this.downloadChunked(url, contentType)
        } else {
          // Check if server supports Range requests (only check once)
          if (supportsRanges === null) {
            supportsRanges = await this.checkRangeSupport(url)
          }

          if (supportsRanges) {
            console.debug(`Attempt ${attempt + 1}: Range requests for ${url}`)
            return await this.downloadWithRanges(url, contentType)
          } else {
            console.debug(`Attempt ${attempt + 1}: Chunked streaming (no range support) for ${url}`)
            return await this.downloadChunked(url, contentType)
          }
        }
      } catch (error) {
        lastError = error
        console.warn(`Download attempt ${attempt + 1} failed for ${url}:`, error.message)
      }
    }

    throw lastError
  }

  // Simple download - fastest but may fail on bad WiFi
  async downloadSimple(url, contentType) {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(30000) // 30 second timeout
    })

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }

    return await response.blob()
  }

  // Download file in chunks using streaming - better timeout detection
  async downloadChunked(url, contentType) {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(60000) // 60 second timeout
    })

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }

    const reader = response.body.getReader()
    const chunks = []

    // Read chunks from stream
    while (true) {
      const { done, value } = await reader.read()

      if (done) break

      chunks.push(value)
    }

    // Combine chunks into single blob
    const blob = new Blob(chunks, { type: contentType })
    return blob
  }

  // Check if server supports Range requests
  async checkRangeSupport(url) {
    try {
      const response = await fetch(url, {
        method: 'HEAD',
        signal: AbortSignal.timeout(5000)
      })

      const acceptRanges = response.headers.get('Accept-Ranges')
      return acceptRanges === 'bytes'
    } catch (error) {
      console.warn('Failed to check Range support:', error)
      return false
    }
  }

  // Download using Range requests - bypasses size limits by making multiple small requests
  async downloadWithRanges(url, contentType, chunkSize = 512 * 1024) {
    // First, get the file size
    const headResponse = await fetch(url, {
      method: 'HEAD',
      signal: AbortSignal.timeout(5000)
    })

    if (!headResponse.ok) {
      throw new Error(`HTTP error! status: ${headResponse.status}`)
    }

    const contentLength = parseInt(headResponse.headers.get('Content-Length'))
    if (!contentLength) {
      throw new Error('Content-Length header missing')
    }

    console.debug(`Downloading ${contentLength} bytes in ${chunkSize} byte chunks`)

    const chunks = []
    let start = 0

    // Download in chunks
    while (start < contentLength) {
      const end = Math.min(start + chunkSize - 1, contentLength - 1)

      const response = await fetch(url, {
        headers: {
          'Range': `bytes=${start}-${end}`
        },
        signal: AbortSignal.timeout(30000) // 30 second timeout per chunk
      })

      if (!response.ok && response.status !== 206) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const chunk = await response.arrayBuffer()
      chunks.push(new Uint8Array(chunk))

      start = end + 1
    }

    // Combine all chunks into single blob
    const blob = new Blob(chunks, { type: contentType })
    return blob
  }

  // IndexedDB initialization
  async initDB() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open('ShowcaseSongs', 1)

      request.onerror = () => reject(request.error)
      request.onsuccess = () => resolve(request.result)

      request.onupgradeneeded = (event) => {
        const db = event.target.result

        // Create object store if it doesn't exist
        if (!db.objectStoreNames.contains('songs')) {
          const objectStore = db.createObjectStore('songs', { keyPath: 'url' })
          objectStore.createIndex('eventId', 'eventId', { unique: false })
          objectStore.createIndex('cachedAt', 'cachedAt', { unique: false })
        }
      }
    })
  }

  // Get cached song from IndexedDB
  // Extract base URL without query parameters (for stable cache keys)
  getBaseUrl(url) {
    try {
      const urlObj = new URL(url)
      return urlObj.origin + urlObj.pathname
    } catch (error) {
      return url
    }
  }

  async getCachedSong(url) {
    const baseUrl = this.getBaseUrl(url)
    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction(['songs'], 'readonly')
      const objectStore = transaction.objectStore('songs')
      const request = objectStore.get(baseUrl)

      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
  }

  // Store song in IndexedDB
  async storeSong(url, blob, contentType) {
    const baseUrl = this.getBaseUrl(url)
    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction(['songs'], 'readwrite')
      const objectStore = transaction.objectStore('songs')

      const song = {
        url: baseUrl,  // Use base URL as stable key
        blob: blob,
        contentType: contentType,
        cachedAt: Date.now(),
        eventId: this.eventIdValue || 'unknown',
        size: blob.size
      }

      const request = objectStore.put(song)

      request.onsuccess = () => resolve()
      request.onerror = () => reject(request.error)
    })
  }

  // Get all cached songs
  async getAllCachedSongs() {
    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction(['songs'], 'readonly')
      const objectStore = transaction.objectStore('songs')
      const request = objectStore.getAll()

      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
  }

  // Delete song from IndexedDB
  async deleteSong(url) {
    const baseUrl = this.getBaseUrl(url)
    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction(['songs'], 'readwrite')
      const objectStore = transaction.objectStore('songs')
      const request = objectStore.delete(baseUrl)

      request.onsuccess = () => resolve()
      request.onerror = () => reject(request.error)
    })
  }

  // Cleanup expired songs (older than 30 days)
  async cleanupExpired() {
    const maxAge = 30 * 24 * 60 * 60 * 1000 // 30 days
    const now = Date.now()

    try {
      const allSongs = await this.getAllCachedSongs()

      for (const song of allSongs) {
        if (now - song.cachedAt > maxAge) {
          await this.deleteSong(song.url)
          console.log(`[Cache] Deleted expired song: ${song.url}`)
        }
      }
    } catch (error) {
      console.warn('Failed to cleanup expired songs:', error)
    }
  }

  // Auto-restore cached songs on page load
  async restoreCachedSongs() {
    const audioElements = document.querySelectorAll("audio[controls]")

    for (const audio of audioElements) {
      const source = audio.querySelector("source")
      if (!source) continue

      const url = source.src

      // Skip if already a data URL
      if (url.startsWith("data:")) continue

      // Check IndexedDB
      const cached = await this.getCachedSong(url)

      if (cached) {
        try {
          // Replace with cached version using Object URL
          source.src = URL.createObjectURL(cached.blob)
          audio.load()

          // Mark as cached
          const row = audio.closest('tr')
          if (row) row.classList.add('cached')
        } catch (error) {
          console.warn(`Failed to restore cached song ${url}:`, error)
        }
      }
    }
  }

  // Update cache statistics display
  async updateCacheStats() {
    if (!this.hasStatsTarget) return

    try {
      const allSongs = await this.getAllCachedSongs()
      const eventSongs = allSongs.filter(s => s.eventId === this.eventIdValue)

      const totalSize = eventSongs.reduce((sum, song) => sum + song.size, 0)
      const sizeMB = (totalSize / (1024 * 1024)).toFixed(1)

      const audioElements = document.querySelectorAll("audio[controls]")
      const totalSongs = audioElements.length

      if (eventSongs.length > 0) {
        const oldestCached = Math.min(...eventSongs.map(s => s.cachedAt))
        const daysAgo = Math.floor((Date.now() - oldestCached) / (1000 * 60 * 60 * 24))
        const timeText = daysAgo === 0 ? 'today' : `${daysAgo} day${daysAgo === 1 ? '' : 's'} ago`

        this.statsTarget.textContent = `${eventSongs.length} of ${totalSongs} songs cached (${sizeMB} MB) • Cached ${timeText}`

        // Update clear button text
        if (this.hasClearButtonTarget) {
          this.clearButtonTarget.textContent = `Clear Cache`
          this.clearButtonTarget.classList.remove('hidden')
        }
      } else {
        this.statsTarget.textContent = `No songs cached yet`
        if (this.hasClearButtonTarget) {
          this.clearButtonTarget.classList.add('hidden')
        }
      }
    } catch (error) {
      console.warn('Failed to update cache stats:', error)
    }
  }

  // Clear all cached songs for this event
  async clearCache() {
    if (!confirm('Clear all cached songs? You will need to download them again.')) {
      return
    }

    try {
      const allSongs = await this.getAllCachedSongs()
      const eventSongs = allSongs.filter(s => s.eventId === this.eventIdValue)

      for (const song of eventSongs) {
        await this.deleteSong(song.url)
      }

      // Reload page to reset audio elements
      window.location.reload()
    } catch (error) {
      console.error('Failed to clear cache:', error)
      alert('Failed to clear cache. Check console for details.')
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
