import { Controller } from "@hotwired/stimulus"
import { heatDataManager } from "helpers/heat_data_manager"
import { connectivityTracker } from "helpers/connectivity_tracker"

// Displays connection status and pending scores count
// Used in the SPA scoring interface to show offline state
export default class extends Controller {
  static targets = ["pending", "onlineIcon", "offlineIcon"]
  static values = {
    judge: Number
  }

  connect() {
    // Initial state
    this.updateDisplay()

    // Listen for connectivity changes
    this.connectivityHandler = this.handleConnectivityChange.bind(this)
    document.addEventListener('connectivity-changed', this.connectivityHandler)

    // Listen for pending count changes
    this.pendingHandler = this.updatePendingCount.bind(this)
    document.addEventListener('pending-count-changed', this.pendingHandler)

    // Listen for browser online/offline events
    this.onlineHandler = () => this.updateDisplay()
    this.offlineHandler = () => this.updateDisplay()
    window.addEventListener('online', this.onlineHandler)
    window.addEventListener('offline', this.offlineHandler)

    // Initial pending count
    this.updatePendingCount()
  }

  disconnect() {
    document.removeEventListener('connectivity-changed', this.connectivityHandler)
    document.removeEventListener('pending-count-changed', this.pendingHandler)
    window.removeEventListener('online', this.onlineHandler)
    window.removeEventListener('offline', this.offlineHandler)
  }

  handleConnectivityChange(event) {
    this.updateDisplay()
    this.updatePendingCount()
  }

  updateDisplay() {
    const connected = connectivityTracker.getStatus() && navigator.onLine

    if (this.hasOnlineIconTarget && this.hasOfflineIconTarget) {
      // Show online icon when connected, offline icon when not
      this.onlineIconTarget.classList.toggle('hidden', !connected)
      this.offlineIconTarget.classList.toggle('hidden', connected)
    }
  }

  async updatePendingCount() {
    if (!this.hasJudgeValue || !this.hasPendingTarget) return

    try {
      // Ensure manager is initialized
      await heatDataManager.init()
      const count = await heatDataManager.getDirtyScoreCount(this.judgeValue)

      if (count > 0) {
        this.pendingTarget.textContent = count
        // Show offline icon when there are pending scores
        if (this.hasOnlineIconTarget && this.hasOfflineIconTarget) {
          this.onlineIconTarget.classList.add('hidden')
          this.offlineIconTarget.classList.remove('hidden')
        }
      } else {
        this.pendingTarget.textContent = ''
        // Restore normal display based on connectivity
        this.updateDisplay()
      }
    } catch (error) {
      console.debug('[ConnectionStatus] Failed to get pending count:', error)
    }
  }
}
