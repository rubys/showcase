/**
 * DirtyScoresQueue - Manages offline score queueing with IndexedDB
 *
 * Handles score persistence when offline and automatic upload when connectivity returns.
 * Uses IndexedDB for reliable offline storage with automatic cleanup after successful uploads.
 */
export class DirtyScoresQueue {
  constructor(dbName = 'ShowcaseScores', storeName = 'dirtyScores') {
    this.dbName = dbName
    this.storeName = storeName
    this.db = null
  }

  /**
   * Initialize IndexedDB connection
   * Creates the database and object store if they don't exist
   */
  async init() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, 1)

      request.onerror = () => reject(request.error)
      request.onsuccess = () => {
        this.db = request.result
        resolve()
      }

      request.onupgradeneeded = (event) => {
        const db = event.target.result
        if (!db.objectStoreNames.contains(this.storeName)) {
          // Create object store with auto-incrementing key
          const objectStore = db.createObjectStore(this.storeName, { keyPath: 'id', autoIncrement: true })
          // Index by heat_id for quick lookups
          objectStore.createIndex('heat_id', 'heat_id', { unique: false })
          // Index by timestamp for ordering
          objectStore.createIndex('timestamp', 'timestamp', { unique: false })
        }
      }
    })
  }

  /**
   * Add a score to the dirty queue
   * @param {Object} scoreData - Score data to queue { heat_id, value, good, bad, comments }
   * @returns {Promise<number>} The ID of the queued score
   */
  async add(scoreData) {
    if (!this.db) await this.init()

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([this.storeName], 'readwrite')
      const store = transaction.objectStore(this.storeName)

      const record = {
        ...scoreData,
        timestamp: Date.now()
      }

      const request = store.add(record)

      request.onsuccess = () => {
        console.debug('[DirtyScoresQueue] Added score to queue:', record)
        resolve(request.result)
      }
      request.onerror = () => reject(request.error)
    })
  }

  /**
   * Get all queued scores
   * @returns {Promise<Array>} Array of queued score records
   */
  async getAll() {
    if (!this.db) await this.init()

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([this.storeName], 'readonly')
      const store = transaction.objectStore(this.storeName)
      const request = store.getAll()

      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
  }

  /**
   * Get count of queued scores
   * @returns {Promise<number>} Number of scores in queue
   */
  async count() {
    if (!this.db) await this.init()

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([this.storeName], 'readonly')
      const store = transaction.objectStore(this.storeName)
      const request = store.count()

      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
  }

  /**
   * Remove a score from the queue
   * @param {number} id - The ID of the score to remove
   * @returns {Promise<void>}
   */
  async remove(id) {
    if (!this.db) await this.init()

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([this.storeName], 'readwrite')
      const store = transaction.objectStore(this.storeName)
      const request = store.delete(id)

      request.onsuccess = () => {
        console.debug('[DirtyScoresQueue] Removed score from queue:', id)
        resolve()
      }
      request.onerror = () => reject(request.error)
    })
  }

  /**
   * Clear all queued scores
   * @returns {Promise<void>}
   */
  async clear() {
    if (!this.db) await this.init()

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([this.storeName], 'readwrite')
      const store = transaction.objectStore(this.storeName)
      const request = store.clear()

      request.onsuccess = () => {
        console.debug('[DirtyScoresQueue] Cleared all scores from queue')
        resolve()
      }
      request.onerror = () => reject(request.error)
    })
  }

  /**
   * Upload all queued scores to the server
   * Removes successfully uploaded scores from the queue
   * @param {string} csrfToken - CSRF token for POST requests
   * @returns {Promise<Object>} Upload results { successful, failed, errors }
   */
  async uploadAll(csrfToken) {
    const scores = await this.getAll()
    if (scores.length === 0) {
      return { successful: 0, failed: 0, errors: [] }
    }

    console.log(`[DirtyScoresQueue] Uploading ${scores.length} queued scores...`)

    let successful = 0
    let failed = 0
    const errors = []

    for (const score of scores) {
      try {
        const response = await this.uploadScore(score, csrfToken)

        if (response.ok) {
          // Remove from queue after successful upload
          await this.remove(score.id)
          successful++
          console.debug('[DirtyScoresQueue] Uploaded and removed:', score.id)
        } else {
          failed++
          const errorText = await response.text()
          errors.push({ score, error: `HTTP ${response.status}: ${errorText}` })
          console.error('[DirtyScoresQueue] Upload failed:', score.id, response.status)
        }
      } catch (error) {
        failed++
        errors.push({ score, error: error.message })
        console.error('[DirtyScoresQueue] Upload error:', score.id, error)
      }
    }

    console.log(`[DirtyScoresQueue] Upload complete: ${successful} successful, ${failed} failed`)
    return { successful, failed, errors }
  }

  /**
   * Upload a single score to the server
   * @param {Object} score - Score record to upload
   * @param {string} csrfToken - CSRF token for POST request
   * @returns {Promise<Response>} Fetch response
   */
  async uploadScore(score, csrfToken) {
    const formData = new FormData()

    // Add score fields
    if (score.value !== undefined && score.value !== null) {
      formData.append('score[value]', score.value)
    }
    if (score.good !== undefined && score.good !== null) {
      formData.append('score[good]', score.good)
    }
    if (score.bad !== undefined && score.bad !== null) {
      formData.append('score[bad]', score.bad)
    }
    if (score.comments) {
      formData.append('score[comments]', score.comments)
    }

    return fetch(`/heats/${score.heat_id}/score`, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': csrfToken
      },
      body: formData
    })
  }

  /**
   * Get scores for a specific heat
   * @param {number} heatId - Heat ID to filter by
   * @returns {Promise<Array>} Array of score records for the heat
   */
  async getByHeatId(heatId) {
    if (!this.db) await this.init()

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([this.storeName], 'readonly')
      const store = transaction.objectStore(this.storeName)
      const index = store.index('heat_id')
      const request = index.getAll(heatId)

      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
  }
}
