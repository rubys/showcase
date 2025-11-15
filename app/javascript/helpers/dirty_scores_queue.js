/**
 * DirtyScoresQueue - IndexedDB management for offline score queue
 *
 * Manages the queue of scores that failed to upload or were entered offline.
 * Uses IndexedDB for persistence across page reloads.
 */

const DB_NAME = 'showcase_dirty_scores';
const DB_VERSION = 1;
const STORE_NAME = 'dirty_scores';

class DirtyScoresQueue {
  constructor() {
    this.db = null;
    this.initPromise = null;
  }

  /**
   * Initialize the IndexedDB database
   * @returns {Promise<IDBDatabase>}
   */
  async init() {
    console.debug('[DirtyScoresQueue] init called, DB version:', DB_VERSION);
    if (this.db) {
      console.debug('[DirtyScoresQueue] DB already initialized');
      return this.db;
    }

    return new Promise((resolve, reject) => {
      console.debug('[DirtyScoresQueue] Opening IndexedDB...');
      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onerror = () => {
        console.error('[DirtyScoresQueue] Failed to open IndexedDB:', request.error);
        reject(request.error);
      };

      request.onblocked = () => {
        console.warn('[DirtyScoresQueue] IndexedDB upgrade blocked - close other tabs or connections');
      };

      request.onsuccess = () => {
        console.debug('[DirtyScoresQueue] IndexedDB opened successfully');
        this.db = request.result;
        resolve(this.db);
      };

      request.onupgradeneeded = (event) => {
        console.debug('[DirtyScoresQueue] Upgrade needed, old version:', event.oldVersion, 'new version:', event.newVersion);
        const db = event.target.result;

        // Delete old store if it exists (for schema changes)
        if (db.objectStoreNames.contains(STORE_NAME)) {
          console.debug('[DirtyScoresQueue] Deleting old object store');
          db.deleteObjectStore(STORE_NAME);
        }

        // Create object store for dirty scores
        console.debug('[DirtyScoresQueue] Creating dirty scores object store');
        const objectStore = db.createObjectStore(STORE_NAME, { keyPath: 'judge_id' });
        objectStore.createIndex('timestamp', 'timestamp', { unique: false });
        console.debug('[DirtyScoresQueue] Object store created');
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
   * @param {number|null} slot - The slot number (default 1)
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
        // Normalize slot: treat null as 1 for consistency
        const normalizedSlot = slot || 1;
        const key = `${heatId}-${normalizedSlot}`;
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
          console.debug(`Dirty score added for judge ${judgeId}, heat ${heatId}, slot ${slot}`);
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
   * Get count of dirty scores for a judge
   * @param {number} judgeId - The judge ID
   * @returns {Promise<number>}
   */
  async getDirtyScoreCount(judgeId) {
    const dirtyScores = await this.getDirtyScores(judgeId);
    return dirtyScores.length;
  }

  /**
   * Remove a specific dirty score (after successful upload)
   * @param {number} judgeId - The judge ID
   * @param {number} heatId - The heat ID
   * @param {number|null} slot - The slot number (default 1)
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
          console.debug(`Dirty score removed for judge ${judgeId}, heat ${heatId}, slot ${slot}`);
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
          console.debug(`All dirty scores cleared for judge ${judgeId}`);
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
}

// Export singleton instance
export const dirtyScoresQueue = new DirtyScoresQueue();
