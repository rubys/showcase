/**
 * HeatPage - Main orchestrator component for SPA scoring
 *
 * Simple design:
 * - On init: Upload dirty scores → Fetch fresh data from server
 * - On navigation: Use in-memory data (no cache checks)
 * - On score update: Update in-memory + POST to server (or queue if offline)
 * - Server is always source of truth for heat data
 * - IndexedDB only stores dirty scores (pending uploads)
 *
 * This component:
 * - Manages navigation between heats
 * - Renders appropriate heat type component
 * - Handles keyboard and swipe navigation
 * - Integrates with score submission
 *
 * Usage:
 *   <heat-page judge-id="123" heat-number="1" style="radio"></heat-page>
 */

import { heatDataManager } from 'helpers/heat_data_manager';
import HeatNavigator from 'helpers/heat_navigator';

// Import heat type components
import { HeatSolo } from 'components/heat-types/heat-solo';
import { HeatRank } from 'components/heat-types/heat-rank';
import { HeatTable } from 'components/heat-types/heat-table';
import { HeatCards } from 'components/heat-types/heat-cards';

// Import shared components
import { HeatHeader } from 'components/shared/heat-header';
import { HeatInfoBox } from 'components/shared/heat-info-box';
import { HeatNavigation } from 'components/shared/heat-navigation';

// Import heat list component
import { HeatList } from 'components/heat-list';

export class HeatPage extends HTMLElement {
  connectedCallback() {
    // Make this element transparent in layout - don't interfere with child layout
    const nativeStyle = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'style').get.call(this);
    nativeStyle.display = 'contents';

    this.judgeId = parseInt(this.getAttribute('judge-id'));
    const heatAttr = this.getAttribute('heat-number');
    this.currentHeatNumber = heatAttr ? parseInt(heatAttr) : null;
    this.scoringStyle = this.getAttribute('scoring-style') || 'radio';
    this.slot = parseInt(this.getAttribute('slot') || '0');
    this.basePath = this.getAttribute('base-path') || '';

    this.data = null;
    this.touchStart = null;
    this.dataManager = heatDataManager; // Make data manager accessible to child components

    // Set base path in data manager
    heatDataManager.setBasePath(this.basePath);

    // Create navigator
    this.navigator = new HeatNavigator(this);

    this.init();
  }

  disconnectedCallback() {
    this.removeEventListeners();
    if (this.navigator) {
      this.navigator.destroy();
    }
  }

  /**
   * Initialize - upload dirty scores and load fresh data
   */
  async init() {
    try {
      console.debug('[HeatPage] Starting initialization for judge', this.judgeId);

      // Show loading state
      this.innerHTML = '<div class="flex items-center justify-center h-screen"><div class="text-2xl">Loading heat data...</div></div>';

      // First, batch upload any pending dirty scores
      console.debug('[HeatPage] Checking for dirty scores...');
      await heatDataManager.batchUploadDirtyScores(this.judgeId);

      // Then fetch fresh data from server
      console.debug('[HeatPage] Fetching fresh data...');
      this.data = await heatDataManager.getData(this.judgeId);
      console.debug('[HeatPage] Data loaded:', this.data ? 'success' : 'failed');

      if (!this.data) {
        throw new Error('Failed to load heat data');
      }

      // Listen for online event to batch upload dirty scores
      window.addEventListener('online', () => this.handleReconnection());

      // Initial render
      console.debug('[HeatPage] Rendering...');
      this.render();
      console.debug('[HeatPage] Render complete');

      // Attach event listeners
      this.attachEventListeners();

    } catch (error) {
      console.error('Failed to initialize heat page:', error);
      this.innerHTML = `
        <div class="flex items-center justify-center h-screen">
          <div class="text-2xl text-red-500">
            Failed to load heat data. Please check your connection and try again.
            <br><br>
            Error: ${error.message}
            <br><br>
            <button onclick="location.reload()" class="btn-blue">Retry</button>
          </div>
        </div>
      `;
    }
  }

  /**
   * Check for dirty scores and batch upload if any exist
   */
  async checkAndUploadDirtyScores() {
    try {
      const result = await heatDataManager.batchUploadDirtyScores(this.judgeId);

      if (result.succeeded && result.succeeded.length > 0) {
        console.debug(`[HeatPage] Successfully uploaded ${result.succeeded.length} scores`);
        // Refresh data after successful upload
        this.data = await heatDataManager.getData(this.judgeId);
        this.render();
      }

      if (result.failed && result.failed.length > 0) {
        console.warn(`[HeatPage] Failed to upload ${result.failed.length} scores`);
      }
    } catch (error) {
      console.error('[HeatPage] Failed to check/upload dirty scores:', error);
    }
  }

  /**
   * Handle reconnection - batch upload dirty scores and refresh data
   */
  async handleReconnection() {
    console.debug('[HeatPage] Reconnected to network');
    await this.checkAndUploadDirtyScores();
  }

  /**
   * Handle score update - update in-memory data
   * (Actual save is handled by HeatDataManager in heat-table.js)
   */
  handleScoreUpdate(scoreData) {
    if (!this.data || !this.data.heats) return;

    // Find the heat by ID
    const heat = this.data.heats.find(h =>
      h.subjects.some(s => s.id === scoreData.heat)
    );

    if (!heat) return;

    // Find the subject
    const subject = heat.subjects.find(s => s.id === scoreData.heat);
    if (!subject) return;

    // Find or create the judge's score
    let judgeScore = subject.scores.find(s => s.judge_id === this.data.judge.id);

    if (!judgeScore) {
      judgeScore = {
        judge_id: this.data.judge.id,
        heat_id: heat.id,
        value: null,
        comments: null
      };
      subject.scores.push(judgeScore);
    }

    // Update the in-memory score data
    // Handle both 'score' (regular scores) and 'value' (feedback scores)
    if (scoreData.score !== undefined || scoreData.value !== undefined) {
      judgeScore.value = scoreData.score || scoreData.value;
    }
    if (scoreData.comments !== undefined) {
      judgeScore.comments = scoreData.comments;
    }
    if (scoreData.good !== undefined) {
      judgeScore.good = scoreData.good;
    }
    if (scoreData.bad !== undefined) {
      judgeScore.bad = scoreData.bad;
    }

    console.debug('[HeatPage] Score updated in memory');
  }


  /**
   * Check server version and refetch data if changed
   */
  async checkVersionAndRefetch() {
    try {
      // Fetch version from server
      const versionUrl = `${this.basePath}/scores/${this.judgeId}/version/${this.currentHeatNumber}`;
      const response = await fetch(versionUrl);

      if (!response.ok) {
        // Offline or error - use cached data
        console.debug('[HeatPage] Version check failed, using cached data (offline)');
        heatDataManager.updateConnectivity(false);
        return;
      }

      const serverVersion = await response.json();

      // Update connectivity status (success)
      heatDataManager.updateConnectivity(true, this.judgeId);

      const cachedVersion = heatDataManager.getCachedVersion();

      // Compare versions
      if (this.isVersionCurrent(cachedVersion, serverVersion)) {
        // Versions match - use cached data
        console.debug('[HeatPage] Version check: data is current, using cache');
        return;
      }

      // Versions differ - refetch full data
      console.debug('[HeatPage] Version check: data changed, refetching', {
        cached: cachedVersion,
        server: serverVersion
      });

      this.data = await heatDataManager.getData(this.judgeId, true); // Force refetch
    } catch (error) {
      // Network error - use cached data
      console.debug('[HeatPage] Version check failed, using cached data (error):', error.message);
      heatDataManager.updateConnectivity(false);
    }
  }

  /**
   * Compare cached and server versions
   */
  isVersionCurrent(cachedVersion, serverVersion) {
    if (!cachedVersion || !serverVersion) return false;

    return (
      cachedVersion.max_updated_at === serverVersion.max_updated_at &&
      cachedVersion.heat_count === serverVersion.heat_count
    );
  }


  /**
   * Determine which heat type component to use
   */
  getHeatTypeComponent() {
    const heat = this.navigator.getCurrentHeat();
    if (!heat) return null;

    if (heat.category === 'Solo') {
      return 'heat-solo';
    }

    // Check if this is a final (scrutineering final round)
    const isFinal = heat.dance.uses_scrutineering &&
                    (this.slot > (heat.dance.heat_length || 0) || heat.subjects.length <= 8);

    if (isFinal) {
      return 'heat-rank';
    }

    // Check for cards style
    if (this.scoringStyle === 'cards' && this.scoringStyle !== 'emcee' && heat.scoring && !['#', '+', '&', '@'].includes(heat.scoring)) {
      return 'heat-cards';
    }

    // Default to table
    return 'heat-table';
  }

  /**
   * Sort subjects based on judge's sort_order setting
   * Matches ERB logic from scores_controller.rb:467-487
   */
  sortSubjects(subjects) {
    const sortOrder = this.data.judge.sort_order || 'back';
    const showAssignments = this.data.judge.show_assignments || 'first';
    const assignJudges = this.data.event.assign_judges > 0;

    // Create a copy to avoid mutating original
    let sorted = [...subjects];

    // Initial sort by assignment priority (if applicable) and back number
    if (assignJudges && showAssignments !== 'mixed') {
      sorted.sort((a, b) => {
        const aAssigned = a.scores?.some(s => s.judge_id === this.data.judge.id) ? 0 : 1;
        const bAssigned = b.scores?.some(s => s.judge_id === this.data.judge.id) ? 0 : 1;

        if (aAssigned !== bAssigned) return aAssigned - bAssigned;
        if (a.dance_id !== b.dance_id) return a.dance_id - b.dance_id;
        return (a.lead.back || 0) - (b.lead.back || 0);
      });
    } else {
      sorted.sort((a, b) => {
        if (a.dance_id !== b.dance_id) return a.dance_id - b.dance_id;
        return (a.lead.back || 0) - (b.lead.back || 0);
      });
    }

    // Apply level sort if requested
    if (sortOrder === 'level') {
      sorted.sort((a, b) => {
        // Assignment priority first (if applicable)
        if (assignJudges && showAssignments !== 'mixed') {
          const aAssigned = a.scores?.some(s => s.judge_id === this.data.judge.id) ? 0 : 1;
          const bAssigned = b.scores?.some(s => s.judge_id === this.data.judge.id) ? 0 : 1;
          if (aAssigned !== bAssigned) return aAssigned - bAssigned;
        }

        // Then by level_id, age_id, and back number
        const aLevelId = a.level?.id || 0;
        const bLevelId = b.level?.id || 0;
        if (aLevelId !== bLevelId) return aLevelId - bLevelId;

        const aAgeId = a.age?.id || 0;
        const bAgeId = b.age?.id || 0;
        if (aAgeId !== bAgeId) return aAgeId - bAgeId;

        return (a.lead.back || 0) - (b.lead.back || 0);
      });
    }

    return sorted;
  }

  /**
   * Build heat type component
   */
  buildHeatTypeComponent() {
    const heat = this.navigator.getCurrentHeat();
    if (!heat) return '<div class="text-center text-red-500">Heat not found</div>';

    const componentType = this.getHeatTypeComponent();

    // Common attributes
    let attrs = `
      heat-data='${this.escapeJson(heat)}'
      event-data='${this.escapeJson(this.data.event)}'
      judge-data='${this.escapeJson(this.data.judge)}'
      scoring-style="${this.scoringStyle}"
      drop-action="/scores/${this.judgeId}/post"
      start-action="/events/start_heat"
    `;

    if (componentType === 'heat-table' || componentType === 'heat-cards') {
      // Need scores and results for table/cards
      const scores = this.data.score_options[heat.category] || [];
      attrs += ` scores='${this.escapeJson(scores)}'`;

      // Build results map (score -> subjects with that score)
      const results = {};
      scores.forEach(score => results[score] = []);

      heat.subjects.forEach(subject => {
        const judgeScore = subject.scores.find(s => s.judge_id === this.data.judge.id);
        const scoreValue = judgeScore?.value || '';
        if (!results[scoreValue]) results[scoreValue] = [];
        results[scoreValue].push(subject);
      });

      attrs += ` results='${this.escapeJson(results)}'`;

      // Add ballrooms for table
      if (componentType === 'heat-table') {
        // Sort subjects according to judge's sort_order setting
        const sortedSubjects = this.sortSubjects(heat.subjects);
        // Group subjects by ballroom (simplified - would need actual ballroom logic)
        const ballrooms = { '': sortedSubjects };
        attrs += ` ballrooms='${this.escapeJson(ballrooms)}'`;
        attrs += ` scoring="${heat.scoring}"`;
        attrs += ` feedbacks='${this.escapeJson(this.data.feedbacks)}'`;
        attrs += ` assign-judges="${this.data.event.assign_judges > 0}"`;
      }
    }

    if (componentType === 'heat-rank') {
      attrs += ` slot="${this.slot}"`;
    }

    return `<${componentType} ${attrs}></${componentType}>`;
  }

  /**
   * Handle keyboard navigation
   */
  handleKeydown(event) {
    const isFormElement = ['INPUT', 'TEXTAREA'].includes(event.target.nodeName) ||
                         ['INPUT', 'TEXTAREA'].includes(document.activeElement?.nodeName);

    if (event.key === 'ArrowRight' && !isFormElement) {
      event.preventDefault();
      this.navigator.navigateNext();
    } else if (event.key === 'ArrowLeft' && !isFormElement) {
      event.preventDefault();
      this.navigator.navigatePrev();
    } else if (event.key === 'Escape') {
      if (document.activeElement) document.activeElement.blur();
    }
  }

  /**
   * Handle touch events for swipe navigation
   */
  handleTouchStart(event) {
    this.touchStart = event.touches[0];
  }

  handleTouchEnd(event) {
    if (!this.touchStart) return;

    const touchEnd = event.changedTouches[0];
    if (touchEnd.identifier !== this.touchStart.identifier) return;

    const deltaX = touchEnd.clientX - this.touchStart.clientX;
    const deltaY = touchEnd.clientY - this.touchStart.clientY;

    const width = document.documentElement.clientWidth;
    const height = document.documentElement.clientHeight;

    if (Math.abs(deltaX) > width / 2 && Math.abs(deltaY) < height / 4) {
      if (deltaX > 0) {
        this.navigator.navigatePrev();
      } else {
        this.navigator.navigateNext();
      }
    }

    this.touchStart = null;
  }

  /**
   * Attach event listeners (called once in connectedCallback)
   */
  attachEventListeners() {
    // Keyboard and touch handlers on document.body
    this.keydownHandler = (e) => this.handleKeydown(e);
    this.touchStartHandler = (e) => this.handleTouchStart(e);
    this.touchEndHandler = (e) => this.handleTouchEnd(e);

    document.body.addEventListener('keydown', this.keydownHandler);
    document.body.addEventListener('touchstart', this.touchStartHandler);
    document.body.addEventListener('touchend', this.touchEndHandler);

    // Listen for navigation events from heat-navigation component
    this.addEventListener('navigate-prev', () => {
      this.navigator.navigatePrev();
    });

    this.addEventListener('navigate-next', () => {
      this.navigator.navigateNext();
    });

    // Listen for heat selection from heat-list
    this.addEventListener('navigate-to-heat', (e) => {
      const heatNumber = e.detail.heat;
      this.navigator.navigateToHeat(heatNumber, 0);
    });

    // Listen for score updates to update in-memory data
    this.addEventListener('score-updated', (e) => {
      this.handleScoreUpdate(e.detail);
    });

    // Listen for scores-synced event (after successful batch upload on reconnection)
    this.scoresSyncedHandler = async () => {
      console.debug('[HeatPage] Scores synced - refreshing data');
      this.data = await heatDataManager.getData(this.judgeId);
      this.render();
    };
    document.addEventListener('scores-synced', this.scoresSyncedHandler);
  }

  /**
   * Escape HTML entities in JSON for safe embedding in attributes
   * Prevents XSS and JSON parsing errors from quotes/apostrophes
   */
  escapeJson(obj) {
    return JSON.stringify(obj)
      .replace(/&/g, '&amp;')
      .replace(/'/g, '&apos;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  /**
   * Remove event listeners
   */
  removeEventListeners() {
    if (this.keydownHandler) {
      document.body.removeEventListener('keydown', this.keydownHandler);
      document.body.removeEventListener('touchstart', this.touchStartHandler);
      document.body.removeEventListener('touchend', this.touchEndHandler);
    }
    if (this.scoresSyncedHandler) {
      document.removeEventListener('scores-synced', this.scoresSyncedHandler);
    }
    this.listenersAttached = false;
  }

  /**
   * Main render method
   */
  render() {
    if (!this.data) return;

    // If no heat number, show heat list with navigation footer
    if (this.currentHeatNumber === null) {
      this.innerHTML = `
        <div class="flex flex-col h-screen max-h-screen w-full">
          <div class="flex-1 overflow-auto">
            <heat-list judge-id="${this.judgeId}" scoring-style="${this.scoringStyle}" base-path="${this.basePath}"></heat-list>
          </div>
          <heat-navigation
            judge-data='${JSON.stringify(this.data.judge)}'
            event-data='${JSON.stringify(this.data.event)}'
            prev-url=""
            next-url=""
            assign-judges="${this.data.event.assign_judges > 0}"
            base-path="${this.basePath}"
            root-path="/">
          </heat-navigation>
        </div>
      `;
      const heatList = this.querySelector('heat-list');
      heatList.setData(this.data);
      return;
    }

    const heat = this.navigator.getCurrentHeat();
    if (!heat) {
      this.innerHTML = '<div class="text-center text-red-500">Heat not found</div>';
      return;
    }

    const { prevUrl, nextUrl } = this.navigator.getNavigationUrls();

    this.innerHTML = `
      <div class="flex flex-col h-screen max-h-screen w-full">
        <heat-header
          heat-data='${this.escapeJson(heat)}'
          event-data='${this.escapeJson(this.data.event)}'
          judge-data='${this.escapeJson(this.data.judge)}'
          scoring-style="${this.scoringStyle}"
          slot="${this.slot}"
          final="${heat.dance.uses_scrutineering && this.slot > (heat.dance.heat_length || 0)}"
          base-path="${this.basePath}">
        </heat-header>

        <heat-info-box
          heat-data='${this.escapeJson(heat)}'
          event-data='${this.escapeJson(this.data.event)}'
          scoring-style="${this.scoringStyle}">
        </heat-info-box>

        <div class="flex-1 flex flex-col overflow-hidden">
          <div class="flex-1 flex flex-row overflow-hidden">
            ${this.buildHeatTypeComponent()}
          </div>

          <heat-navigation
            judge-data='${this.escapeJson(this.data.judge)}'
            event-data='${this.escapeJson(this.data.event)}'
            prev-url="${prevUrl}"
            next-url="${nextUrl}"
            assign-judges="${this.data.event.assign_judges > 0}"
            root-path="/">
          </heat-navigation>
        </div>
      </div>
    `;
  }
}

customElements.define('heat-page', HeatPage);
