/**
 * HeatDataManager - IndexedDB wrapper for storing and retrieving heat data
 *
 * This class manages offline storage of heat data downloaded from the server.
 * It uses IndexedDB to store the complete heat list and individual heat data.
 */

const DB_NAME = 'showcase_heats';
const DB_VERSION = 4;  // Bumped to add version metadata and dirty scores tracking
const STORE_NAME = 'heats';

class HeatDataManager {
  constructor() {
    this.db = null;
    this.initPromise = this.init();
    this.inactivityTimer = null;
    this.INACTIVITY_TIMEOUT = 5 * 60 * 1000; // 5 minutes

    // Close immediately when tab hidden (Page Visibility API)
    document.addEventListener('visibilitychange', () => {
      if (document.hidden && this.db) {
        console.log('[HeatDataManager] Tab hidden, closing IndexedDB');
        this.closeDB();
      }
    });
  }

  /**
   * Initialize the IndexedDB database
   * @returns {Promise<IDBDatabase>}
   */
  async init() {
    console.log('[HeatDataManager] init called, DB version:', DB_VERSION);
    if (this.db) {
      console.log('[HeatDataManager] DB already initialized');
      return this.db;
    }

    return new Promise((resolve, reject) => {
      console.log('[HeatDataManager] Opening IndexedDB...');
      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onerror = () => {
        console.error('[HeatDataManager] Failed to open IndexedDB:', request.error);
        reject(request.error);
      };

      request.onblocked = () => {
        console.warn('[HeatDataManager] IndexedDB upgrade blocked - close other tabs or connections');
        // Try to continue anyway - the success handler will eventually fire
      };

      request.onsuccess = () => {
        console.log('[HeatDataManager] IndexedDB opened successfully');
        this.db = request.result;
        resolve(this.db);
      };

      request.onupgradeneeded = (event) => {
        console.log('[HeatDataManager] Upgrade needed, old version:', event.oldVersion, 'new version:', event.newVersion);
        const db = event.target.result;

        // Delete old store if it exists (for schema changes)
        if (db.objectStoreNames.contains(STORE_NAME)) {
          console.log('[HeatDataManager] Deleting old object store');
          db.deleteObjectStore(STORE_NAME);
        }

        // Create object store
        console.log('[HeatDataManager] Creating new object store');
        const objectStore = db.createObjectStore(STORE_NAME, { keyPath: 'judge_id' });

        // Create index on timestamp for backwards compatibility
        objectStore.createIndex('timestamp', 'timestamp', { unique: false });
        console.log('[HeatDataManager] Object store created');
      };
    });
  }

  /**
   * Ensure database connection is open (lazy open pattern)
   * @returns {Promise<IDBDatabase>}
   */
  async ensureOpen() {
    if (!this.db) {
      await this.init();
    }
    return this.db;
  }

  /**
   * Close the database connection
   */
  closeDB() {
    if (this.db) {
      console.log('[HeatDataManager] Closing IndexedDB connection');
      this.db.close();
      this.db = null;
    }
    this.clearInactivityTimer();
  }

  /**
   * Clear the inactivity timeout timer
   */
  clearInactivityTimer() {
    if (this.inactivityTimer) {
      clearTimeout(this.inactivityTimer);
      this.inactivityTimer = null;
    }
  }

  /**
   * Reset the inactivity timeout timer
   * Called after any score update operation
   */
  resetInactivityTimer() {
    this.clearInactivityTimer();
    this.inactivityTimer = setTimeout(() => {
      console.log('[HeatDataManager] Inactivity timeout, closing IndexedDB');
      this.closeDB();
    }, this.INACTIVITY_TIMEOUT);
  }

  /**
   * Store heat data for a judge
   * @param {number} judgeId - The judge ID
   * @param {Object} data - The complete heat data from the server
   * @param {Object} version - Optional version metadata {max_updated_at, heat_count}
   * @returns {Promise<void>}
   */
  async storeHeatData(judgeId, data, version = null) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);

      // First get existing record to preserve dirty_scores
      const getRequest = objectStore.get(judgeId);

      getRequest.onsuccess = () => {
        const existing = getRequest.result;

        const record = {
          judge_id: judgeId,
          data: data,
          timestamp: Date.now(),
          version: version,
          dirty_scores: existing?.dirty_scores || []
        };

        const putRequest = objectStore.put(record);

        putRequest.onsuccess = () => {
          console.log(`Heat data stored for judge ${judgeId}`);
          this.resetInactivityTimer();
          resolve();
        };

        putRequest.onerror = () => {
          console.error('Failed to store heat data:', putRequest.error);
          reject(putRequest.error);
        };
      };

      getRequest.onerror = () => {
        console.error('Failed to get existing data:', getRequest.error);
        reject(getRequest.error);
      };
    });
  }

  /**
   * Retrieve heat data for a judge
   * @param {number} judgeId - The judge ID
   * @returns {Promise<Object|null>}
   */
  async getHeatData(judgeId) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readonly');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        if (request.result) {
          resolve(request.result.data);
        } else {
          resolve(null);
        }
      };

      request.onerror = () => {
        console.error('Failed to retrieve heat data:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Get cached version metadata for a judge
   * @param {number} judgeId - The judge ID
   * @returns {Promise<Object|null>} Version metadata {max_updated_at, heat_count}
   */
  async getVersion(judgeId) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readonly');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        resolve(request.result?.version || null);
      };

      request.onerror = () => {
        console.error('Failed to retrieve version:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Add or update a dirty score (score pending upload)
   * Uses "last update wins" - if score already exists for this heat/slot, it's replaced
   * @param {number} judgeId - The judge ID
   * @param {number} heatId - The heat ID
   * @param {number} slot - The slot number (default 1)
   * @param {Object} scoreData - Score data {score, comments, good, bad}
   * @returns {Promise<void>}
   */
  async addDirtyScore(judgeId, heatId, slot = 1, scoreData) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        const record = request.result || {
          judge_id: judgeId,
          data: null,
          timestamp: Date.now(),
          version: null,
          dirty_scores: []
        };

        // Find existing dirty score for this heat/slot
        const key = `${heatId}-${slot}`;
        const existingIndex = record.dirty_scores.findIndex(
          s => `${s.heat}-${s.slot || 1}` === key
        );

        const dirtyScore = {
          heat: heatId,
          slot: slot,
          score: scoreData.score,
          comments: scoreData.comments,
          good: scoreData.good,
          bad: scoreData.bad,
          timestamp: Date.now()
        };

        if (existingIndex >= 0) {
          // Replace existing (last update wins)
          record.dirty_scores[existingIndex] = dirtyScore;
        } else {
          // Add new
          record.dirty_scores.push(dirtyScore);
        }

        const putRequest = objectStore.put(record);

        putRequest.onsuccess = () => {
          console.log(`Dirty score added for judge ${judgeId}, heat ${heatId}, slot ${slot}`);
          this.resetInactivityTimer();
          resolve();
        };

        putRequest.onerror = () => {
          console.error('Failed to add dirty score:', putRequest.error);
          reject(putRequest.error);
        };
      };

      request.onerror = () => {
        console.error('Failed to get record for dirty score:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Get all dirty scores for a judge
   * @param {number} judgeId - The judge ID
   * @returns {Promise<Array>} Array of dirty score objects
   */
  async getDirtyScores(judgeId) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readonly');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        resolve(request.result?.dirty_scores || []);
      };

      request.onerror = () => {
        console.error('Failed to retrieve dirty scores:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Remove a specific dirty score (after successful upload)
   * @param {number} judgeId - The judge ID
   * @param {number} heatId - The heat ID
   * @param {number} slot - The slot number (default 1)
   * @returns {Promise<void>}
   */
  async removeDirtyScore(judgeId, heatId, slot = 1) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        const record = request.result;
        if (!record) {
          resolve(); // No record, nothing to remove
          return;
        }

        const key = `${heatId}-${slot}`;
        record.dirty_scores = record.dirty_scores.filter(
          s => `${s.heat}-${s.slot || 1}` !== key
        );

        const putRequest = objectStore.put(record);

        putRequest.onsuccess = () => {
          console.log(`Dirty score removed for judge ${judgeId}, heat ${heatId}, slot ${slot}`);
          this.resetInactivityTimer();
          resolve();
        };

        putRequest.onerror = () => {
          console.error('Failed to remove dirty score:', putRequest.error);
          reject(putRequest.error);
        };
      };

      request.onerror = () => {
        console.error('Failed to get record for dirty score removal:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Clear all dirty scores for a judge (after successful batch upload)
   * @param {number} judgeId - The judge ID
   * @returns {Promise<void>}
   */
  async clearDirtyScores(judgeId) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        const record = request.result;
        if (!record) {
          resolve(); // No record, nothing to clear
          return;
        }

        record.dirty_scores = [];

        const putRequest = objectStore.put(record);

        putRequest.onsuccess = () => {
          console.log(`All dirty scores cleared for judge ${judgeId}`);
          this.resetInactivityTimer();
          resolve();
        };

        putRequest.onerror = () => {
          console.error('Failed to clear dirty scores:', putRequest.error);
          reject(putRequest.error);
        };
      };

      request.onerror = () => {
        console.error('Failed to get record for clearing dirty scores:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Get a specific heat by number
   * @param {number} judgeId - The judge ID
   * @param {number} heatNumber - The heat number to retrieve
   * @returns {Promise<Object|null>}
   */
  async getHeat(judgeId, heatNumber) {
    const data = await this.getHeatData(judgeId);
    if (!data || !data.heats) return null;

    return data.heats.find(heat => heat.number === heatNumber) || null;
  }

  /**
   * Check if cached version matches server version
   * @param {number} judgeId - The judge ID
   * @param {Object} serverVersion - Server version {max_updated_at, heat_count}
   * @returns {Promise<boolean>} True if versions match, false if refresh needed
   */
  async isVersionCurrent(judgeId, serverVersion) {
    const cachedVersion = await this.getVersion(judgeId);

    if (!cachedVersion || !serverVersion) {
      return false; // No cached version = needs refresh
    }

    // Compare both max_updated_at and heat_count
    const sameTimestamp = cachedVersion.max_updated_at === serverVersion.max_updated_at;
    const sameCount = cachedVersion.heat_count === serverVersion.heat_count;

    return sameTimestamp && sameCount;
  }

  /**
   * Check server version for a specific heat
   * @param {number} judgeId - The judge ID
   * @param {number} heatNumber - The heat number for logging purposes
   * @returns {Promise<Object|null>} Server version {max_updated_at, heat_count, heat_number}
   */
  async checkServerVersion(judgeId, heatNumber) {
    const url = `/scores/${judgeId}/version/${heatNumber}`;

    try {
      const response = await fetch(url, {
        headers: window.inject_region({
          'Accept': 'application/json'
        }),
        credentials: 'same-origin'
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      return await response.json();
    } catch (error) {
      console.error('[HeatDataManager] Failed to check server version:', error);
      return null; // Return null on error (will be treated as offline)
    }
  }

  /**
   * Delete heat data for a judge
   * @param {number} judgeId - The judge ID
   * @returns {Promise<void>}
   */
  async deleteHeatData(judgeId) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.delete(judgeId);

      request.onsuccess = () => {
        console.log(`Heat data deleted for judge ${judgeId}`);
        resolve();
      };

      request.onerror = () => {
        console.error('Failed to delete heat data:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Clear all stored heat data
   * @returns {Promise<void>}
   */
  async clearAll() {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.clear();

      request.onsuccess = () => {
        console.log('All heat data cleared');
        resolve();
      };

      request.onerror = () => {
        console.error('Failed to clear heat data:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Fetch and store heat data from the server
   * @param {number} judgeId - The judge ID
   * @param {number} heatNumber - Optional heat number for version check
   * @returns {Promise<Object>}
   */
  async fetchAndStore(judgeId, heatNumber = null) {
    const url = `/scores/${judgeId}/heats.json`;
    console.log('[HeatDataManager] fetchAndStore: fetching from', url);

    try {
      console.log('[HeatDataManager] Making fetch request...');
      const response = await fetch(url, {
        headers: window.inject_region({
          'Accept': 'application/json'
        }),
        credentials: 'same-origin'
      });
      console.log('[HeatDataManager] Fetch response received, status:', response.status);

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      console.log('[HeatDataManager] Parsing JSON...');
      const data = await response.json();
      console.log('[HeatDataManager] JSON parsed');

      // Get version from server (if heat number provided)
      let version = null;
      if (heatNumber !== null) {
        version = await this.checkServerVersion(judgeId, heatNumber);
      }

      console.log('[HeatDataManager] Storing to IndexedDB...');
      // Try to store to IndexedDB with a timeout, but don't fail if it hangs
      try {
        const timeoutPromise = new Promise((_, reject) =>
          setTimeout(() => reject(new Error('Store timeout')), 2000)
        );
        await Promise.race([this.storeHeatData(judgeId, data, version), timeoutPromise]);
        console.log('[HeatDataManager] Data stored successfully');
      } catch (storeError) {
        console.warn('[HeatDataManager] Failed to store to IndexedDB (continuing anyway):', storeError.message);
        // Continue anyway - we have the data even if we couldn't cache it
      }

      return data;
    } catch (error) {
      console.error('[HeatDataManager] Failed to fetch heat data:', error);
      throw error;
    }
  }

  /**
   * Get heat data, fetching from server if not cached or version mismatch
   * @param {number} judgeId - The judge ID
   * @param {number} heatNumber - Optional heat number for version check
   * @param {boolean} forceRefresh - Force fetch from server even if cached
   * @returns {Promise<Object>}
   */
  async getData(judgeId, heatNumber = null, forceRefresh = false) {
    console.log('[HeatDataManager] getData called for judge', judgeId, 'heat:', heatNumber, 'forceRefresh:', forceRefresh);

    if (!forceRefresh) {
      try {
        console.log('[HeatDataManager] Checking for cached data...');

        // Race between checking cache and a timeout
        const timeoutPromise = new Promise((_, reject) =>
          setTimeout(() => reject(new Error('IndexedDB timeout')), 2000)
        );

        const cached = await Promise.race([this.getHeatData(judgeId), timeoutPromise]);
        console.log('[HeatDataManager] Cached data:', cached ? 'found' : 'not found');

        if (cached && heatNumber !== null) {
          // Check version with server
          const serverVersion = await this.checkServerVersion(judgeId, heatNumber);

          if (serverVersion) {
            const isCurrent = await this.isVersionCurrent(judgeId, serverVersion);
            console.log('[HeatDataManager] Version check - current:', isCurrent);

            if (isCurrent) {
              console.log('[HeatDataManager] Using cached heat data (version matches)');
              return cached;
            } else {
              console.log('[HeatDataManager] Version mismatch, fetching fresh data');
            }
          } else {
            // Server version check failed (offline?) - use cached data
            console.log('[HeatDataManager] Server version check failed, using cached data (offline mode)');
            return cached;
          }
        } else if (cached) {
          // No heat number provided, use cached data if available
          console.log('[HeatDataManager] Using cached heat data (no version check)');
          return cached;
        }
      } catch (error) {
        console.warn('[HeatDataManager] Failed to check cache, will fetch fresh:', error.message);
        // Continue to fetch fresh data
      }
    }

    console.log('[HeatDataManager] Fetching fresh heat data from server');
    return await this.fetchAndStore(judgeId, heatNumber);
  }

  /**
   * Batch upload dirty scores to server
   * @param {number} judgeId - The judge ID
   * @returns {Promise<Object>} {succeeded: [], failed: []}
   */
  async batchUploadDirtyScores(judgeId) {
    const dirtyScores = await this.getDirtyScores(judgeId);

    if (dirtyScores.length === 0) {
      console.log('[HeatDataManager] No dirty scores to upload');
      return { succeeded: [], failed: [] };
    }

    console.log(`[HeatDataManager] Uploading ${dirtyScores.length} dirty scores`);

    const url = `/scores/${judgeId}/batch`;

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: window.inject_region({
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        }),
        credentials: 'same-origin',
        body: JSON.stringify({ scores: dirtyScores })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();

      // Clear dirty scores on success
      if (result.succeeded && result.succeeded.length > 0) {
        await this.clearDirtyScores(judgeId);
        console.log(`[HeatDataManager] Batch upload successful: ${result.succeeded.length} scores uploaded`);
      }

      return result;
    } catch (error) {
      console.error('[HeatDataManager] Failed to batch upload dirty scores:', error);
      return { succeeded: [], failed: dirtyScores.map(s => ({ ...s, error: error.message })) };
    }
  }
}

// Export singleton instance
export const heatDataManager = new HeatDataManager();
