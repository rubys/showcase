/**
 * HeatDataManager - IndexedDB wrapper for storing and retrieving heat data
 *
 * This class manages offline storage of heat data downloaded from the server.
 * It uses IndexedDB to store the complete heat list and individual heat data.
 */

const DB_NAME = 'showcase_heats';
const DB_VERSION = 3;  // Bumped to invalidate cache after adding studio to lead/follow
const STORE_NAME = 'heats';

class HeatDataManager {
  constructor() {
    this.db = null;
    this.initPromise = this.init();
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

        // Create index on timestamp for staleness checks
        objectStore.createIndex('timestamp', 'timestamp', { unique: false });
        console.log('[HeatDataManager] Object store created');
      };
    });
  }

  /**
   * Store heat data for a judge
   * @param {number} judgeId - The judge ID
   * @param {Object} data - The complete heat data from the server
   * @returns {Promise<void>}
   */
  async storeHeatData(judgeId, data) {
    await this.initPromise;

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);

      const record = {
        judge_id: judgeId,
        data: data,
        timestamp: Date.now()
      };

      const request = objectStore.put(record);

      request.onsuccess = () => {
        console.log(`Heat data stored for judge ${judgeId}`);
        resolve();
      };

      request.onerror = () => {
        console.error('Failed to store heat data:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Retrieve heat data for a judge
   * @param {number} judgeId - The judge ID
   * @returns {Promise<Object|null>}
   */
  async getHeatData(judgeId) {
    await this.initPromise;

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
   * Check if the stored data is stale (older than specified age)
   * @param {number} judgeId - The judge ID
   * @param {number} maxAge - Maximum age in milliseconds (default: 1 hour)
   * @returns {Promise<boolean>}
   */
  async isStale(judgeId, maxAge = 60 * 60 * 1000) {
    await this.initPromise;

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readonly');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        if (!request.result) {
          resolve(true); // No data = stale
        } else {
          const age = Date.now() - request.result.timestamp;
          resolve(age > maxAge);
        }
      };

      request.onerror = () => {
        console.error('Failed to check staleness:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Delete heat data for a judge
   * @param {number} judgeId - The judge ID
   * @returns {Promise<void>}
   */
  async deleteHeatData(judgeId) {
    await this.initPromise;

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
    await this.initPromise;

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
   * @returns {Promise<Object>}
   */
  async fetchAndStore(judgeId) {
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
      console.log('[HeatDataManager] JSON parsed, storing to IndexedDB...');

      // Try to store to IndexedDB with a timeout, but don't fail if it hangs
      try {
        const timeoutPromise = new Promise((_, reject) =>
          setTimeout(() => reject(new Error('Store timeout')), 2000)
        );
        await Promise.race([this.storeHeatData(judgeId, data), timeoutPromise]);
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
   * Get heat data, fetching from server if not cached or stale
   * @param {number} judgeId - The judge ID
   * @param {boolean} forceRefresh - Force fetch from server even if cached
   * @returns {Promise<Object>}
   */
  async getData(judgeId, forceRefresh = false) {
    console.log('[HeatDataManager] getData called for judge', judgeId, 'forceRefresh:', forceRefresh);

    if (!forceRefresh) {
      try {
        console.log('[HeatDataManager] Checking for cached data...');

        // Race between checking cache and a timeout
        const timeoutPromise = new Promise((_, reject) =>
          setTimeout(() => reject(new Error('IndexedDB timeout')), 2000)
        );

        const cached = await Promise.race([this.getHeatData(judgeId), timeoutPromise]);
        console.log('[HeatDataManager] Cached data:', cached ? 'found' : 'not found');

        if (cached) {
          const stale = await this.isStale(judgeId);
          console.log('[HeatDataManager] Cache is stale:', stale);

          if (!stale) {
            console.log('[HeatDataManager] Using cached heat data');
            return cached;
          }
        }
      } catch (error) {
        console.warn('[HeatDataManager] Failed to check cache, will fetch fresh:', error.message);
        // Continue to fetch fresh data
      }
    }

    console.log('[HeatDataManager] Fetching fresh heat data from server');
    return await this.fetchAndStore(judgeId);
  }
}

// Export singleton instance
export const heatDataManager = new HeatDataManager();
