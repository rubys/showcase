/**
 * HeatNavigator - Navigation orchestration for heat SPA
 *
 * Handles navigation between heats including:
 * - Next/previous heat
 * - Navigate to specific heat
 * - Browser back/forward (popstate)
 * - Slot navigation for multi-slot heats
 * - Heat filtering based on judge preferences
 */

class HeatNavigator {
  constructor(heatPage) {
    this.heatPage = heatPage;
    this.setupPopstateListener();
  }

  /**
   * Navigate to a specific heat
   */
  async navigateToHeat(heatNumber, slot = 0) {
    this.heatPage.currentHeatNumber = parseInt(heatNumber);
    this.heatPage.slot = parseInt(slot);

    // Update URL without reload - stay on SPA route
    const url = new URL(window.location);
    url.searchParams.set('heat', this.heatPage.currentHeatNumber);
    if (this.heatPage.slot > 0) {
      url.searchParams.set('slot', this.heatPage.slot);
    } else {
      url.searchParams.delete('slot');
    }
    url.searchParams.set('style', this.heatPage.scoringStyle);
    window.history.pushState({}, '', url);

    // Check version and conditionally refetch data
    await this.heatPage.checkVersionAndRefetch();

    // Render with current data (either cached or freshly fetched)
    this.heatPage.render();
  }

  /**
   * Navigate to next heat
   */
  navigateNext() {
    const heat = this.getCurrentHeat();
    if (!heat) return;

    // Check if we need to navigate to next slot or next heat
    if (heat.dance.heat_length && this.heatPage.slot > 0) {
      const maxSlots = heat.dance.heat_length * (heat.dance.uses_scrutineering ? 2 : 1);
      if (this.heatPage.slot < maxSlots) {
        this.navigateToHeat(this.heatPage.currentHeatNumber, this.heatPage.slot + 1);
        return;
      }
    }

    // Find next heat
    const heats = this.getFilteredHeats();
    const currentIndex = heats.findIndex(h => h.number === this.heatPage.currentHeatNumber);

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
    if (this.heatPage.slot > 1) {
      this.navigateToHeat(this.heatPage.currentHeatNumber, this.heatPage.slot - 1);
      return;
    }

    // Find previous heat
    const heats = this.getFilteredHeats();
    const currentIndex = heats.findIndex(h => h.number === this.heatPage.currentHeatNumber);

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
   * Get current heat data
   */
  getCurrentHeat() {
    if (!this.heatPage.data || !this.heatPage.data.heats) return null;
    return this.heatPage.data.heats.find(h => h.number === this.heatPage.currentHeatNumber);
  }

  /**
   * Get filtered heats based on judge preferences
   */
  getFilteredHeats() {
    if (!this.heatPage.data || !this.heatPage.data.heats) return [];

    const showSolos = this.heatPage.data.judge.review_solos;
    let heats = this.heatPage.data.heats;

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
    const currentIndex = heats.findIndex(h => h.number === this.heatPage.currentHeatNumber);
    const heat = this.getCurrentHeat();

    let prevUrl = '';
    let nextUrl = '';

    // Previous (use SPA route format)
    if (this.heatPage.slot > 1) {
      prevUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${this.heatPage.currentHeatNumber}&slot=${this.heatPage.slot - 1}&style=${this.heatPage.scoringStyle}`;
    } else if (currentIndex > 0) {
      const prevHeat = heats[currentIndex - 1];
      if (prevHeat.dance.heat_length) {
        const maxSlots = prevHeat.dance.heat_length * (prevHeat.dance.uses_scrutineering ? 2 : 1);
        prevUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${prevHeat.number}&slot=${maxSlots}&style=${this.heatPage.scoringStyle}`;
      } else {
        prevUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${prevHeat.number}&style=${this.heatPage.scoringStyle}`;
      }
    }

    // Next (use SPA route format)
    if (heat && heat.dance.heat_length && this.heatPage.slot > 0) {
      const maxSlots = heat.dance.heat_length * (heat.dance.uses_scrutineering ? 2 : 1);
      if (this.heatPage.slot < maxSlots) {
        nextUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${this.heatPage.currentHeatNumber}&slot=${this.heatPage.slot + 1}&style=${this.heatPage.scoringStyle}`;
      }
    }

    if (!nextUrl && currentIndex >= 0 && currentIndex < heats.length - 1) {
      const nextHeat = heats[currentIndex + 1];
      if (nextHeat.dance.heat_length) {
        nextUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${nextHeat.number}&slot=1&style=${this.heatPage.scoringStyle}`;
      } else {
        nextUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${nextHeat.number}&style=${this.heatPage.scoringStyle}`;
      }
    }

    return { prevUrl, nextUrl };
  }

  /**
   * Setup popstate listener for browser back/forward buttons
   */
  setupPopstateListener() {
    this.popstateHandler = (event) => {
      console.debug('[HeatNavigator] Popstate event - URL changed via browser navigation');
      // Read heat number and slot from URL
      const url = new URL(window.location);
      const heatParam = url.searchParams.get('heat');
      const slotParam = url.searchParams.get('slot');
      const styleParam = url.searchParams.get('style');

      if (heatParam) {
        const newHeatNumber = parseInt(heatParam);
        const newSlot = slotParam ? parseInt(slotParam) : 0;
        const newStyle = styleParam || 'radio';

        // Update internal state
        this.heatPage.currentHeatNumber = newHeatNumber;
        this.heatPage.slot = newSlot;
        this.heatPage.scoringStyle = newStyle;

        // Check version and render
        this.heatPage.checkVersionAndRefetch().then(() => {
          this.heatPage.render();
        });
      } else {
        // No heat parameter - show heat list
        this.heatPage.currentHeatNumber = null;
        this.heatPage.render();
      }
    };
    window.addEventListener('popstate', this.popstateHandler);
  }

  /**
   * Remove popstate listener
   */
  removePopstateListener() {
    if (this.popstateHandler) {
      window.removeEventListener('popstate', this.popstateHandler);
    }
  }

  /**
   * Cleanup
   */
  destroy() {
    this.removePopstateListener();
  }
}

export default HeatNavigator;
