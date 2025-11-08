/**
 * HeatDataManager - Manages dirty scores queue for offline sync
 *
 * Simple design:
 * - Server is source of truth for heat data (always fetch fresh)
 * - IndexedDB only stores dirty scores (pending uploads)
 * - On init: Upload dirty scores → Fetch fresh data
 * - On navigation: Use in-memory data (no cache, no version checks)
 */

const DB_NAME = 'showcase_dirty_scores';
const DB_VERSION = 1;
const STORE_NAME = 'dirty_scores';

class HeatDataManager {
  constructor() {
    this.db = null;
    this.initPromise = null;
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

        // Create object store for dirty scores
        console.log('[HeatDataManager] Creating dirty scores object store');
        const objectStore = db.createObjectStore(STORE_NAME, { keyPath: 'judge_id' });
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
      if (!this.initPromise) {
        this.initPromise = this.init();
      }
      await this.initPromise;
    }
    return this.db;
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
          timestamp: Date.now(),
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
   * Fetch heat data from the server (always fetches fresh)
   * @param {number} judgeId - The judge ID
   * @returns {Promise<Object>}
   */
  async getData(judgeId) {
    const url = `/scores/${judgeId}/heats.json`;
    console.log('[HeatDataManager] Fetching fresh data from', url);

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

      const data = await response.json();
      console.log('[HeatDataManager] Data fetched successfully');
      return data;
    } catch (error) {
      console.error('[HeatDataManager] Failed to fetch heat data:', error);
      throw error;
    }
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
