/**
 * HeatDataManager - Simplified data fetching and caching
 *
 * Responsibilities:
 * - Fetch heat data from server
 * - Cache version metadata
 * - Coordinate score saving (delegates to queue and connectivity)
 * - Batch upload coordination
 */

import ScoreMergeHelper from 'helpers/score_merge_helper';
import { connectivityTracker } from 'helpers/connectivity_tracker';
import { dirtyScoresQueue } from 'helpers/dirty_scores_queue';

class HeatDataManager {
  constructor() {
    this.basePath = '';
    this.cachedVersion = null;
  }

  /**
   * Set the base path for all API requests
   * @param {string} basePath - The base URL path (e.g., "http://localhost:3000/showcase/2025/city/event")
   */
  setBasePath(basePath) {
    this.basePath = basePath;
    console.debug('[HeatDataManager] Base path set to:', basePath);
  }

  /**
   * Initialize dirty scores queue
   */
  async init() {
    await dirtyScoresQueue.init();
  }

  /**
   * Get dirty score count (delegates to queue)
   * @param {number} judgeId - The judge ID
   * @returns {Promise<number>}
   */
  async getDirtyScoreCount(judgeId) {
    return dirtyScoresQueue.getDirtyScoreCount(judgeId);
  }

  /**
   * Get all dirty scores for a judge (delegates to queue)
   * @param {number} judgeId - The judge ID
   * @returns {Promise<Array>}
   */
  async getDirtyScores(judgeId) {
    return dirtyScoresQueue.getDirtyScores(judgeId);
  }

  /**
   * Clear all dirty scores for a judge (delegates to queue)
   * @param {number} judgeId - The judge ID
   * @returns {Promise<void>}
   */
  async clearDirtyScores(judgeId) {
    return dirtyScoresQueue.clearDirtyScores(judgeId);
  }

  /**
   * Add or update a dirty score (delegates to queue)
   * @param {number} judgeId - The judge ID
   * @param {number} heatId - The heat ID
   * @param {number|null} slot - The slot number
   * @param {Object} scoreData - Score data {score, comments, good, bad}
   * @returns {Promise<void>}
   */
  async addDirtyScore(judgeId, heatId, slot, scoreData) {
    return dirtyScoresQueue.addDirtyScore(judgeId, heatId, slot, scoreData);
  }

  /**
   * Remove a specific dirty score (delegates to queue)
   * @param {number} judgeId - The judge ID
   * @param {number} heatId - The heat ID
   * @param {number|null} slot - The slot number
   * @returns {Promise<void>}
   */
  async removeDirtyScore(judgeId, heatId, slot) {
    return dirtyScoresQueue.removeDirtyScore(judgeId, heatId, slot);
  }

  /**
   * Update connectivity status (delegates to tracker)
   * @param {boolean} connected - Whether the network request succeeded
   * @param {number} judgeId - The judge ID
   */
  updateConnectivity(connected, judgeId = null) {
    connectivityTracker.updateConnectivity(
      connected,
      judgeId,
      (id) => this.batchUploadDirtyScores(id),
      () => this.invalidateCache()
    );
  }

  /**
   * Fetch heat data from the server - caches version metadata for comparison
   * @param {number} judgeId - The judge ID
   * @param {boolean} forceRefetch - Force refetch even if cached (default: false)
   * @returns {Promise<Object>}
   */
  async getData(judgeId, forceRefetch = false) {
    const url = `${this.basePath}/scores/${judgeId}/heats.json`;
    console.debug('[HeatDataManager] Fetching data from', url, { forceRefetch });

    try {
      const response = await fetch(url, {
        headers: window.inject_region({
          'Accept': 'application/json'
        }),
        credentials: 'same-origin'
      });

      if (!response.ok) {
        connectivityTracker.updateConnectivity(false);
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();
      console.debug('[HeatDataManager] Data fetched successfully');

      // Update connectivity status (success)
      connectivityTracker.updateConnectivity(
        true,
        judgeId,
        (id) => this.batchUploadDirtyScores(id),
        () => this.invalidateCache()
      );

      // Store version metadata for future comparison
      await this.storeCachedVersion(judgeId, data);

      return data;
    } catch (error) {
      console.error('[HeatDataManager] Failed to fetch heat data:', error);
      connectivityTracker.updateConnectivity(false);
      throw error;
    }
  }

  /**
   * Store version metadata for future comparison
   * @param {number} judgeId - The judge ID
   * @param {Object} data - The heat data (contains version info)
   */
  async storeCachedVersion(judgeId, data) {
    try {
      // Calculate version metadata from heat data
      const heats = data.heats || [];
      let maxUpdatedAt = null;

      heats.forEach(heat => {
        if (heat.updated_at) {
          if (!maxUpdatedAt || heat.updated_at > maxUpdatedAt) {
            maxUpdatedAt = heat.updated_at;
          }
        }
      });

      const version = {
        max_updated_at: maxUpdatedAt,
        heat_count: heats.length
      };

      // Store in memory for quick access
      this.cachedVersion = version;

      console.debug('[HeatDataManager] Cached version stored:', version);
    } catch (error) {
      console.error('[HeatDataManager] Failed to store cached version:', error);
    }
  }

  /**
   * Get the cached version metadata
   * @returns {Object|null} Version metadata {max_updated_at, heat_count} or null
   */
  getCachedVersion() {
    return this.cachedVersion || null;
  }

  /**
   * Invalidate the cached version - forces fresh data fetch on next getData() call
   */
  invalidateCache() {
    console.debug('[HeatDataManager] Cache invalidated');
    this.cachedVersion = null;
  }

  /**
   * Save a score (online or offline)
   * @param {number} judgeId - The judge ID
   * @param {Object} data - Score data {heat, score?, comments?, good?, bad?, slot?}
   * @param {Object} currentScore - Current score values {value?, good?, bad?} for offline merge
   * @returns {Promise<Object>} Response object with score data
   */
  async saveScore(judgeId, data, currentScore = {}) {
    // Determine which endpoint to use based on data type
    // Feedback scores have value/good/bad keys, regular scores have score/comments
    const isFeedback = data.value !== undefined || data.good !== undefined || data.bad !== undefined;
    const url = isFeedback ? `${this.basePath}/scores/${judgeId}/post-feedback` : `${this.basePath}/scores/${judgeId}/post`;

    // Try to save online if connected
    if (navigator.onLine) {
      try {
        const response = await fetch(url, {
          method: 'POST',
          headers: window.inject_region({
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content,
            'Content-Type': 'application/json'
          }),
          credentials: 'same-origin',
          body: JSON.stringify(data)
        });

        if (response.ok) {
          console.debug('[HeatDataManager] Score saved online');

          // Update connectivity status (success)
          connectivityTracker.updateConnectivity(
            true,
            judgeId,
            (id) => this.batchUploadDirtyScores(id),
            () => this.invalidateCache()
          );

          // Parse response to get updated score data
          const responseData = await response.json();

          // Check if there are pending dirty scores
          const dirtyCount = await this.getDirtyScoreCount(judgeId);

          if (dirtyCount > 0) {
            // There are pending scores - add this one with latest value from server response
            // to prevent batch upload from sending stale data
            const scoreData = {
              score: responseData.score || responseData.value,
              comments: responseData.comments,
              good: responseData.good,
              bad: responseData.bad
            };
            await dirtyScoresQueue.addDirtyScore(judgeId, data.heat, data.slot || null, scoreData);

            // Batch upload all pending scores (including this one with updated value)
            this.batchUploadDirtyScores(judgeId).then(result => {
              if (result.succeeded && result.succeeded.length > 0) {
                console.debug('[HeatDataManager] Background upload: synced', result.succeeded.length, 'pending scores');
                // Notify that pending count changed
                document.dispatchEvent(new CustomEvent('pending-count-changed', { bubbles: true }));
              }
            }).catch(err => {
              console.debug('[HeatDataManager] Background upload failed:', err);
            });
          }

          return responseData;
        } else {
          console.warn('[HeatDataManager] Online save failed, falling back to offline');
          connectivityTracker.updateConnectivity(false);
        }
      } catch (error) {
        console.warn('[HeatDataManager] Online save failed, falling back to offline:', error);
        connectivityTracker.updateConnectivity(false);
      }
    }

    // Save offline
    // Merge with current score to preserve all fields (important for batch upload)
    const mergedData = ScoreMergeHelper.mergeForOffline(data, currentScore);

    // Use null for slot if not provided (most heats don't use slots)
    await dirtyScoresQueue.addDirtyScore(judgeId, data.heat, data.slot || null, mergedData);
    console.debug('[HeatDataManager] Score saved offline with merged data:', mergedData);

    // Return optimistic update data - only include fields that were in the request
    // This prevents overwriting existing data (e.g., don't clear 'good' when updating 'value')
    return ScoreMergeHelper.generateOptimisticResponse(data);
  }

  /**
   * Batch upload dirty scores to server
   * @param {number} judgeId - The judge ID
   * @returns {Promise<Object>} {succeeded: [], failed: []}
   */
  async batchUploadDirtyScores(judgeId) {
    const dirtyScores = await dirtyScoresQueue.getDirtyScores(judgeId);

    if (dirtyScores.length === 0) {
      console.debug('[HeatDataManager] No dirty scores to upload');
      return { succeeded: [], failed: [] };
    }

    console.debug(`[HeatDataManager] Uploading ${dirtyScores.length} dirty scores`);

    const url = `${this.basePath}/scores/${judgeId}/batch`;

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
        await dirtyScoresQueue.clearDirtyScores(judgeId);
        console.debug(`[HeatDataManager] Batch upload successful: ${result.succeeded.length} scores uploaded`);
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
