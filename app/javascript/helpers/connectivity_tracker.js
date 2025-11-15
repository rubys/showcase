/**
 * ConnectivityTracker - Network connectivity tracking and event dispatching
 *
 * Tracks actual network connectivity based on request success/failure,
 * dispatches events when connectivity changes, and triggers batch uploads
 * when transitioning from offline to online.
 */

class ConnectivityTracker {
  constructor() {
    this.isConnected = navigator.onLine;
  }

  /**
   * Update connectivity status based on network request success/failure
   * @param {boolean} connected - Whether the network request succeeded
   * @param {number} judgeId - The judge ID (for triggering batch upload on reconnection)
   * @param {Function} batchUploadCallback - Callback to trigger batch upload
   * @param {Function} invalidateCacheCallback - Callback to invalidate cache after successful sync
   */
  updateConnectivity(connected, judgeId = null, batchUploadCallback = null, invalidateCacheCallback = null) {
    const wasConnected = this.isConnected;
    this.isConnected = connected;

    // Dispatch connectivity change event
    if (wasConnected !== connected) {
      console.debug('[ConnectivityTracker] Connectivity changed:',
        wasConnected ? 'online→offline' : 'offline→online');
      document.dispatchEvent(new CustomEvent('connectivity-changed', {
        detail: { connected, wasConnected }
      }));

      // If transitioning from offline to online, trigger batch upload
      if (!wasConnected && connected && judgeId && batchUploadCallback) {
        console.debug('[ConnectivityTracker] Reconnected - triggering batch upload');
        batchUploadCallback(judgeId).then(result => {
          if (result.succeeded && result.succeeded.length > 0) {
            console.debug('[ConnectivityTracker] Reconnection sync:',
              result.succeeded.length, 'scores uploaded');
            document.dispatchEvent(new CustomEvent('pending-count-changed', { bubbles: true }));

            // Invalidate cache so fresh data is fetched on next navigation
            if (invalidateCacheCallback) {
              invalidateCacheCallback();
            }
            // Also trigger immediate refresh if on heat-page
            document.dispatchEvent(new CustomEvent('scores-synced', { bubbles: true }));
          }
        }).catch(err => {
          console.debug('[ConnectivityTracker] Reconnection sync failed:', err);
        });
      }
    }
  }

  /**
   * Get current connectivity status
   * @returns {boolean}
   */
  getStatus() {
    return this.isConnected;
  }
}

// Export singleton instance
export const connectivityTracker = new ConnectivityTracker();
