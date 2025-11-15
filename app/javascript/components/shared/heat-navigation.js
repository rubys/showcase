/**
 * HeatNavigation - Previous/next navigation footer
 *
 * Displays navigation controls for moving between heats:
 * - Previous heat button (<<)
 * - Judge information and logo
 * - Next heat button (>>)
 * - Optional judge presence checkbox (when assign_judges is enabled)
 */

import { heatDataManager } from 'helpers/heat_data_manager';

export class HeatNavigation extends HTMLElement {
  connectedCallback() {
    this.isOnline = navigator.onLine;
    this.pendingCount = 0;
    this.render();
    this.attachEventListeners();
    this.setupOnlineOfflineListeners();
    this.setupConnectivityListener();
    this.updatePendingCount(); // Initial count

    // Listen for score changes to update pending count
    this.handlePendingCountChanged = () => {
      console.debug('[heat-navigation] Received pending-count-changed event');
      this.updatePendingCount();
    };
    document.addEventListener('pending-count-changed', this.handlePendingCountChanged);
  }

  disconnectedCallback() {
    this.removeOnlineOfflineListeners();
    this.removeConnectivityListener();
    if (this.handlePendingCountChanged) {
      document.removeEventListener('pending-count-changed', this.handlePendingCountChanged);
    }
  }

  /**
   * Setup online/offline event listeners
   */
  setupOnlineOfflineListeners() {
    this.handleOnline = () => {
      this.isOnline = true;
      this.updateConnectionStatus();
    };
    this.handleOffline = () => {
      this.isOnline = false;
      this.updateConnectionStatus();
    };
    window.addEventListener('online', this.handleOnline);
    window.addEventListener('offline', this.handleOffline);
  }

  /**
   * Remove online/offline event listeners
   */
  removeOnlineOfflineListeners() {
    if (this.handleOnline) {
      window.removeEventListener('online', this.handleOnline);
    }
    if (this.handleOffline) {
      window.removeEventListener('offline', this.handleOffline);
    }
  }

  /**
   * Setup connectivity change listener (from actual network requests)
   */
  setupConnectivityListener() {
    this.handleConnectivityChanged = (event) => {
      console.debug('[heat-navigation] Connectivity changed:', event.detail);
      this.isOnline = event.detail.connected;
      this.updateConnectionStatus();

      // Update pending count when reconnecting (batch upload may have cleared scores)
      if (event.detail.connected && !event.detail.wasConnected) {
        this.updatePendingCount();
      }
    };
    document.addEventListener('connectivity-changed', this.handleConnectivityChanged);
  }

  /**
   * Remove connectivity change listener
   */
  removeConnectivityListener() {
    if (this.handleConnectivityChanged) {
      document.removeEventListener('connectivity-changed', this.handleConnectivityChanged);
    }
  }

  /**
   * Update connection status display
   */
  updateConnectionStatus() {
    const statusElement = this.querySelector('.connection-status');
    if (statusElement) {
      statusElement.innerHTML = this.buildConnectionStatusHtml();
    }
  }

  /**
   * Update pending count from IndexedDB
   */
  async updatePendingCount() {
    try {
      const judgeId = this.judgeData.id;
      if (!judgeId) return;

      const count = await heatDataManager.getDirtyScoreCount(judgeId);
      console.debug('[heat-navigation] Pending count:', count, 'previous:', this.pendingCount);
      this.pendingCount = count;
      this.updateConnectionStatus();
    } catch (error) {
      console.error('Failed to get pending count:', error);
    }
  }

  get judgeData() {
    return JSON.parse(this.getAttribute('judge-data') || '{}');
  }

  get eventData() {
    return JSON.parse(this.getAttribute('event-data') || '{}');
  }

  get prevUrl() {
    return this.getAttribute('prev-url') || '';
  }

  get nextUrl() {
    return this.getAttribute('next-url') || '';
  }

  get assignJudges() {
    return this.getAttribute('assign-judges') === 'true';
  }

  get logoUrl() {
    return this.getAttribute('logo-url') || '';
  }

  get rootPath() {
    return this.getAttribute('root-path') || '/';
  }

  get basePath() {
    return this.getAttribute('base-path') || '';
  }

  /**
   * Navigate to previous heat
   */
  navigatePrev(event) {
    event.preventDefault();
    if (!this.prevUrl) {
      return;
    }
    // Dispatch custom event for parent heat-page to handle
    this.dispatchEvent(new CustomEvent('navigate-prev', { bubbles: true }));
  }

  /**
   * Navigate to next heat
   */
  navigateNext(event) {
    event.preventDefault();
    if (!this.nextUrl) {
      return;
    }
    // Dispatch custom event for parent heat-page to handle
    this.dispatchEvent(new CustomEvent('navigate-next', { bubbles: true }));
  }

  /**
   * Build WiFi icon (online)
   */
  buildWifiOnlineIcon() {
    return `
      <svg class="h-8 w-8 inline-block" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M5 12.55a11 11 0 0 1 14.08 0"></path>
        <path d="M1.42 9a16 16 0 0 1 21.16 0"></path>
        <path d="M8.53 16.11a6 6 0 0 1 6.95 0"></path>
        <circle cx="12" cy="20" r="1"></circle>
      </svg>
    `;
  }

  /**
   * Build WiFi icon (offline)
   */
  buildWifiOfflineIcon() {
    return `
      <svg class="h-8 w-8 inline-block text-red-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M5 12.55a11 11 0 0 1 14.08 0"></path>
        <path d="M1.42 9a16 16 0 0 1 21.16 0"></path>
        <path d="M8.53 16.11a6 6 0 0 1 6.95 0"></path>
        <circle cx="12" cy="20" r="1"></circle>
        <line x1="1" y1="1" x2="23" y2="23"></line>
      </svg>
    `;
  }

  /**
   * Build connection status HTML
   */
  buildConnectionStatusHtml() {
    // Show offline icon if there are pending scores (regardless of network status)
    if (this.pendingCount > 0) {
      const pendingText = `<span class="text-red-500 font-bold mr-1">${this.pendingCount}</span>`;
      return `${pendingText}${this.buildWifiOfflineIcon()}`;
    } else if (this.isOnline) {
      return this.buildWifiOnlineIcon();
    } else {
      return this.buildWifiOfflineIcon();
    }
  }

  /**
   * Toggle judge presence
   */
  togglePresence(event) {
    const checkbox = event.target;
    const isPresent = checkbox.checked;

    // Send update to server
    fetch(`${this.basePath}/people/${this.judgeData.id}/toggle_present`, {
      method: 'POST',
      headers: window.inject_region({
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Content-Type': 'application/json'
      }),
      credentials: 'same-origin',
      body: JSON.stringify({ present: isPresent })
    }).catch(error => {
      console.error('Failed to update judge presence:', error);
      // Revert checkbox on error
      checkbox.checked = !isPresent;
    });
  }

  /**
   * Attach event listeners
   */
  attachEventListeners() {
    const prevLink = this.querySelector('a[rel="prev"]');
    const nextLink = this.querySelector('a[rel="next"]');
    const presentCheckbox = this.querySelector('input[name="active"]');

    if (prevLink) {
      prevLink.addEventListener('click', (e) => this.navigatePrev(e));
    }

    if (nextLink) {
      nextLink.addEventListener('click', (e) => this.navigateNext(e));
    }

    if (presentCheckbox) {
      presentCheckbox.addEventListener('change', (e) => this.togglePresence(e));
    }
  }

  render() {
    const judge = this.judgeData;
    const prevButton = this.prevUrl ? `<a href="${this.prevUrl}" class="text-2xl lg:text-4xl" rel="prev">&lt;&lt;</a>` : '';
    const nextButton = this.nextUrl ? `<a href="${this.nextUrl}" class="text-2xl lg:text-4xl" rel="next">&gt;&gt;</a>` : '';

    // Build status icons: connection status + logo
    const statusHtml = `
      <div class="absolute right-4 top-4 flex items-center gap-2">
        <span class="connection-status flex items-center">
          ${this.buildConnectionStatusHtml()}
        </span>
        <a href="${this.rootPath}" class="flex items-center">
          <img class="h-8" src="/intertwingly.png" />
        </a>
      </div>
    `;

    let judgeSection = '';
    if (this.assignJudges) {
      const checked = judge.present ? 'checked' : '';
      judgeSection = `
        <h1 class="font-bold text-2xl pt-1 pb-3 flex-1 text-center">
          <input type="checkbox" name="active" ${checked} class="w-6 h-6 mr-3">
          <a href="/people/${judge.id}">${judge.display_name || judge.name}</a>
          ${statusHtml}
        </h1>
      `;
    } else {
      judgeSection = `
        <h1 class="font-bold text-2xl pt-1 pb-3 flex-1 text-center">
          <a href="/people/${judge.id}">${judge.display_name || judge.name}</a>
          ${statusHtml}
        </h1>
      `;
    }

    this.innerHTML = `
      <div class="flex flex-row w-full flex-shrink-0">
        <div class="align-middle">
          ${prevButton}
        </div>
        ${judgeSection}
        <div class="align-middle">
          ${nextButton}
        </div>
      </div>
    `;
  }
}

customElements.define('heat-navigation', HeatNavigation);
