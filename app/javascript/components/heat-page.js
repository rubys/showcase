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

    this.data = null;
    this.touchStart = null;

    this.init();
  }

  disconnectedCallback() {
    this.removeEventListeners();
  }

  /**
   * Initialize - upload dirty scores and load fresh data
   */
  async init() {
    try {
      console.log('[HeatPage] Starting initialization for judge', this.judgeId);

      // Show loading state
      this.innerHTML = '<div class="flex items-center justify-center h-screen"><div class="text-2xl">Loading heat data...</div></div>';

      // First, batch upload any pending dirty scores
      console.log('[HeatPage] Checking for dirty scores...');
      await heatDataManager.batchUploadDirtyScores(this.judgeId);

      // Then fetch fresh data from server
      console.log('[HeatPage] Fetching fresh data...');
      this.data = await heatDataManager.getData(this.judgeId);
      console.log('[HeatPage] Data loaded:', this.data ? 'success' : 'failed');

      if (!this.data) {
        throw new Error('Failed to load heat data');
      }

      // Listen for online event to batch upload dirty scores
      window.addEventListener('online', () => this.handleReconnection());

      // Initial render
      console.log('[HeatPage] Rendering...');
      this.render();
      console.log('[HeatPage] Render complete');

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
        console.log(`[HeatPage] Successfully uploaded ${result.succeeded.length} scores`);
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
    console.log('[HeatPage] Reconnected to network');
    await this.checkAndUploadDirtyScores();
  }

  /**
   * Get current heat data
   */
  getCurrentHeat() {
    if (!this.data || !this.data.heats) return null;
    return this.data.heats.find(h => h.number === this.currentHeatNumber);
  }

  /**
   * Handle score update - update in-memory data and POST to server
   */
  async handleScoreUpdate(scoreData) {
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
    if (scoreData.score !== undefined) {
      judgeScore.value = scoreData.score;
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

    // POST score to server
    try {
      const response = await fetch(`/scores/${this.judgeId}/post`, {
        method: 'POST',
        headers: window.inject_region({
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        }),
        credentials: 'same-origin',
        body: JSON.stringify({
          heat: scoreData.heat,
          slot: scoreData.slot || 1,
          score: scoreData.score || '',
          comments: scoreData.comments || '',
          good: scoreData.good || '',
          bad: scoreData.bad || ''
        })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      console.log('[HeatPage] Score posted successfully');

      // Remove from dirty scores if it was there
      await heatDataManager.removeDirtyScore(
        this.judgeId,
        scoreData.heat,
        scoreData.slot || 1
      );

    } catch (error) {
      console.warn('[HeatPage] Failed to POST score, adding to dirty scores:', error);

      // Add to dirty scores for later upload
      await heatDataManager.addDirtyScore(
        this.judgeId,
        scoreData.heat,
        scoreData.slot || 1,
        {
          score: scoreData.score || '',
          comments: scoreData.comments || '',
          good: scoreData.good || '',
          bad: scoreData.bad || ''
        }
      );
    }
  }

  /**
   * Navigate to a specific heat
   */
  async navigateToHeat(heatNumber, slot = 0) {
    this.currentHeatNumber = parseInt(heatNumber);
    this.slot = parseInt(slot);

    // Update URL without reload - stay on SPA route
    const url = new URL(window.location);
    url.searchParams.set('heat', this.currentHeatNumber);
    if (this.slot > 0) {
      url.searchParams.set('slot', this.slot);
    } else {
      url.searchParams.delete('slot');
    }
    url.searchParams.set('style', this.scoringStyle);
    window.history.pushState({}, '', url);

    // Just render - data is already in memory
    this.render();
  }

  /**
   * Navigate to next heat
   */
  navigateNext() {
    const heat = this.getCurrentHeat();
    if (!heat) return;

    // Check if we need to navigate to next slot or next heat
    if (heat.dance.heat_length && this.slot > 0) {
      const maxSlots = heat.dance.heat_length * (heat.dance.uses_scrutineering ? 2 : 1);
      if (this.slot < maxSlots) {
        this.navigateToHeat(this.currentHeatNumber, this.slot + 1);
        return;
      }
    }

    // Find next heat
    const heats = this.getFilteredHeats();
    const currentIndex = heats.findIndex(h => h.number === this.currentHeatNumber);

    if (currentIndex >= 0 && currentIndex < heats.length - 1) {
      const nextHeat = heats[currentIndex + 1];
      const nextSlot = nextHeat.dance.heat_length ? 1 : 0;
      this.navigateToHeat(nextHeat.number, nextSlot);
    }
  }

  /**
   * Navigate to previous heat
   */
  navigatePrev() {
    const heat = this.getCurrentHeat();
    if (!heat) return;

    // Check if we need to navigate to previous slot
    if (this.slot > 1) {
      this.navigateToHeat(this.currentHeatNumber, this.slot - 1);
      return;
    }

    // Find previous heat
    const heats = this.getFilteredHeats();
    const currentIndex = heats.findIndex(h => h.number === this.currentHeatNumber);

    if (currentIndex > 0) {
      const prevHeat = heats[currentIndex - 1];
      let prevSlot = 0;

      if (prevHeat.dance.heat_length) {
        const maxSlots = prevHeat.dance.heat_length * (prevHeat.dance.uses_scrutineering ? 2 : 1);
        prevSlot = maxSlots;
      }

      this.navigateToHeat(prevHeat.number, prevSlot);
    }
  }

  /**
   * Get filtered heats based on judge preferences
   */
  getFilteredHeats() {
    if (!this.data || !this.data.heats) return [];

    const showSolos = this.data.judge.review_solos;
    let heats = this.data.heats;

    if (showSolos === 'none') {
      heats = heats.filter(h => h.category !== 'Solo');
    } else if (showSolos === 'even') {
      heats = heats.filter(h => h.category !== 'Solo' || h.number % 2 === 0);
    } else if (showSolos === 'odd') {
      heats = heats.filter(h => h.category !== 'Solo' || h.number % 2 === 1);
    }

    return heats;
  }

  /**
   * Get prev/next URLs for navigation
   */
  getNavigationUrls() {
    const heats = this.getFilteredHeats();
    const currentIndex = heats.findIndex(h => h.number === this.currentHeatNumber);
    const heat = this.getCurrentHeat();

    let prevUrl = '';
    let nextUrl = '';

    // Previous
    if (this.slot > 1) {
      prevUrl = `/scores/${this.judgeId}/heat/${this.currentHeatNumber}/${this.slot - 1}`;
    } else if (currentIndex > 0) {
      const prevHeat = heats[currentIndex - 1];
      if (prevHeat.dance.heat_length) {
        const maxSlots = prevHeat.dance.heat_length * (prevHeat.dance.uses_scrutineering ? 2 : 1);
        prevUrl = `/scores/${this.judgeId}/heat/${prevHeat.number}/${maxSlots}`;
      } else {
        prevUrl = `/scores/${this.judgeId}/heat/${prevHeat.number}`;
      }
    }

    // Next
    if (heat && heat.dance.heat_length && this.slot > 0) {
      const maxSlots = heat.dance.heat_length * (heat.dance.uses_scrutineering ? 2 : 1);
      if (this.slot < maxSlots) {
        nextUrl = `/scores/${this.judgeId}/heat/${this.currentHeatNumber}/${this.slot + 1}`;
      }
    }

    if (!nextUrl && currentIndex >= 0 && currentIndex < heats.length - 1) {
      const nextHeat = heats[currentIndex + 1];
      if (nextHeat.dance.heat_length) {
        nextUrl = `/scores/${this.judgeId}/heat/${nextHeat.number}/1`;
      } else {
        nextUrl = `/scores/${this.judgeId}/heat/${nextHeat.number}`;
      }
    }

    return { prevUrl, nextUrl };
  }

  /**
   * Determine which heat type component to use
   */
  getHeatTypeComponent() {
    const heat = this.getCurrentHeat();
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
    const heat = this.getCurrentHeat();
    if (!heat) return '<div class="text-center text-red-500">Heat not found</div>';

    const componentType = this.getHeatTypeComponent();
    const heatData = JSON.stringify(heat);
    const eventData = JSON.stringify(this.data.event);
    const judgeData = JSON.stringify(this.data.judge);

    // Common attributes
    let attrs = `
      heat-data='${heatData}'
      event-data='${eventData}'
      judge-data='${judgeData}'
      scoring-style="${this.scoringStyle}"
      drop-action="/scores/${this.judgeId}/post"
      start-action="/events/start_heat"
    `;

    if (componentType === 'heat-table' || componentType === 'heat-cards') {
      // Need scores and results for table/cards
      const scores = this.data.score_options[heat.category] || [];
      attrs += ` scores='${JSON.stringify(scores)}'`;

      // Build results map (score -> subjects with that score)
      const results = {};
      scores.forEach(score => results[score] = []);

      heat.subjects.forEach(subject => {
        const judgeScore = subject.scores.find(s => s.judge_id === this.data.judge.id);
        const scoreValue = judgeScore?.value || '';
        if (!results[scoreValue]) results[scoreValue] = [];
        results[scoreValue].push(subject);
      });

      attrs += ` results='${JSON.stringify(results)}'`;

      // Add ballrooms for table
      if (componentType === 'heat-table') {
        // Sort subjects according to judge's sort_order setting
        const sortedSubjects = this.sortSubjects(heat.subjects);
        // Group subjects by ballroom (simplified - would need actual ballroom logic)
        const ballrooms = { '': sortedSubjects };
        attrs += ` ballrooms='${JSON.stringify(ballrooms)}'`;
        attrs += ` scoring="${heat.scoring}"`;
        attrs += ` feedbacks='${JSON.stringify(this.data.feedbacks)}'`;
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
      this.navigateNext();
    } else if (event.key === 'ArrowLeft' && !isFormElement) {
      event.preventDefault();
      this.navigatePrev();
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
        this.navigatePrev();
      } else {
        this.navigateNext();
      }
    }

    this.touchStart = null;
  }

  /**
   * Attach event listeners
   */
  attachEventListeners() {
    this.keydownHandler = (e) => this.handleKeydown(e);
    this.touchStartHandler = (e) => this.handleTouchStart(e);
    this.touchEndHandler = (e) => this.handleTouchEnd(e);

    document.body.addEventListener('keydown', this.keydownHandler);
    document.body.addEventListener('touchstart', this.touchStartHandler);
    document.body.addEventListener('touchend', this.touchEndHandler);

    // Listen for navigation events from heat-navigation component
    this.addEventListener('navigate-prev', () => {
      this.navigatePrev();
    });

    this.addEventListener('navigate-next', () => {
      this.navigateNext();
    });

    // Listen for score updates to update in-memory data
    this.addEventListener('score-updated', (e) => {
      this.handleScoreUpdate(e.detail);
    });

    // Also intercept direct link clicks as backup
    this.addEventListener('click', (e) => {
      const link = e.target.closest('a[rel="prev"], a[rel="next"]');
      if (link) {
        e.preventDefault();
        if (link.getAttribute('rel') === 'prev') {
          this.navigatePrev();
        } else {
          this.navigateNext();
        }
      }
    });
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
  }

  /**
   * Main render method
   */
  render() {
    if (!this.data) return;

    // If no heat number, show heat list
    if (this.currentHeatNumber === null) {
      this.innerHTML = '<heat-list judge-id="' + this.judgeId + '" scoring-style="' + this.scoringStyle + '"></heat-list>';
      const heatList = this.querySelector('heat-list');
      heatList.setData(this.data);
      return;
    }

    const heat = this.getCurrentHeat();
    if (!heat) {
      this.innerHTML = '<div class="text-center text-red-500">Heat not found</div>';
      return;
    }

    const { prevUrl, nextUrl } = this.getNavigationUrls();

    this.innerHTML = `
      <div class="flex flex-col h-screen max-h-screen w-full">
        <heat-header
          heat-data='${JSON.stringify(heat)}'
          event-data='${JSON.stringify(this.data.event)}'
          judge-data='${JSON.stringify(this.data.judge)}'
          scoring-style="${this.scoringStyle}"
          slot="${this.slot}"
          final="${heat.dance.uses_scrutineering && this.slot > (heat.dance.heat_length || 0)}">
        </heat-header>

        <heat-info-box
          heat-data='${JSON.stringify(heat)}'
          event-data='${JSON.stringify(this.data.event)}'
          scoring-style="${this.scoringStyle}">
        </heat-info-box>

        <div class="flex-1 flex flex-col overflow-hidden">
          <div class="flex-1 flex flex-row overflow-hidden">
            ${this.buildHeatTypeComponent()}
          </div>

          <heat-navigation
            judge-data='${JSON.stringify(this.data.judge)}'
            event-data='${JSON.stringify(this.data.event)}'
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
