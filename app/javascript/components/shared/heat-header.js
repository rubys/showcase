/**
 * HeatHeader - Displays heat number, dance name, and context information
 *
 * Renders the header for a heat, including:
 * - Heat number and dance name
 * - Combo dance (for solos)
 * - Judge assignments (if applicable)
 * - Emcee information (couples count, song)
 * - Multi-dance slot information
 */

export class HeatHeader extends HTMLElement {
  connectedCallback() {
    this.render();
  }

  get heatData() {
    return JSON.parse(this.getAttribute('heat-data') || '{}');
  }

  get eventData() {
    return JSON.parse(this.getAttribute('event-data') || '{}');
  }

  get judgeData() {
    return JSON.parse(this.getAttribute('judge-data') || '{}');
  }

  get style() {
    return this.getAttribute('scoring-style') || 'radio';
  }

  get slot() {
    return parseInt(this.getAttribute('slot') || '0');
  }

  get final() {
    return this.getAttribute('final') === 'true';
  }

  get callbacks() {
    return this.getAttribute('callbacks');
  }

  /**
   * Calculate dance slot display text
   */
  heatDanceSlotDisplay() {
    const { dance } = this.heatData;
    if (!dance.heat_length) return '';

    const { heat_length, uses_scrutineering } = dance;

    if (!uses_scrutineering) {
      return `Dance ${this.slot} of ${heat_length}:`;
    } else if (!this.final) {
      return `Semi-final ${this.slot} of ${heat_length}:`;
    } else {
      const slotNumber = this.slot > heat_length ? this.slot - heat_length : this.slot;
      return `Final ${slotNumber} of ${heat_length}:`;
    }
  }

  /**
   * Get multi-dance names for current slot
   */
  heatMultiDanceNames() {
    const { dance } = this.heatData;
    if (!dance.multi_children || dance.multi_children.length === 0) return '';

    // Group by slot
    const slots = {};
    dance.multi_children.forEach(child => {
      const slot = child.slot || 1;
      if (!slots[slot]) slots[slot] = [];
      slots[slot].push(child);
    });

    const slotKeys = Object.keys(slots);

    // If multiple slots and current slot has dances
    if (slotKeys.length > 1 && slots[this.slot]) {
      return slots[this.slot]
        .sort((a, b) => a.order - b.order)
        .map(multi => multi.name)
        .join(' / ');
    }

    // If last slot length equals heat_length (rotating pattern)
    const lastSlot = slots[slotKeys[slotKeys.length - 1]];
    if (lastSlot && lastSlot.length === dance.heat_length) {
      const index = (this.slot - 1) % dance.heat_length;
      const multi = lastSlot.sort((a, b) => a.order - b.order)[index];
      return multi?.name || '';
    }

    // Default: show all dances in last slot
    if (lastSlot) {
      return lastSlot
        .sort((a, b) => a.order - b.order)
        .map(multi => multi.name)
        .join(' / ');
    }

    return '';
  }

  /**
   * Display judge back numbers with color coding
   */
  judgeBacksDisplay(heats, unassigned, early) {
    return heats.map(heat => {
      let colorClass = 'text-black';
      if (unassigned.includes(heat)) {
        colorClass = 'text-red-400';
      } else if (early.includes(heat)) {
        colorClass = 'text-gray-400';
      }

      const backNumber = heat.subjects[0]?.lead?.back || '';
      return `<a href="#heat-${heat.id}" class="${colorClass}">${backNumber}</a>`;
    }).join(' ');
  }

  render() {
    const heat = this.heatData;
    const event = this.eventData;
    const judge = this.judgeData;
    const { number, dance, category, subjects } = heat;

    // Build dance name with category (matching ERB logic)
    let danceName = dance.name;
    const combineOpenAndClosed = event.heat_range_cat === 1;

    // Add category prefix unless combining open/closed categories
    if (!(combineOpenAndClosed && ['Open', 'Closed'].includes(category))) {
      danceName = `${category} ${dance.name}`;
    }

    // Build combo dance display
    let comboDanceHtml = '';
    if (category === 'Solo' && heat.solo?.combo_dance_id) {
      comboDanceHtml = ` / ${heat.solo.combo_dance.name}`;
    }

    // Build judge backs display (for assigned judges)
    let judgeBacksHtml = '';
    if (event.assign_judges && judge.show_assignments === 'mixed' && this.style !== 'emcee') {
      // This would need to query for assigned/unassigned heats
      // For now, we'll skip this complex logic and implement it when needed
      // judgeBacksHtml = `<div class="text-2xl">${this.judgeBacksDisplay(...)}</div>`;
    }

    // Build emcee display
    let emceeHtml = '';
    if (this.style === 'emcee' && category !== 'Solo') {
      const couplesCount = subjects.length;
      const couplesWord = couplesCount === 1 ? 'couple' : 'couples';
      emceeHtml = `<div class="font-normal">${couplesCount} ${couplesWord} on the floor</div>`;

      // Add song if available
      if (dance.songs && dance.songs.length > 0) {
        // Calculate which song to show (cycle through songs)
        const songIndex = (number - 1) % dance.songs.length;
        const song = dance.songs[songIndex];
        if (song) {
          emceeHtml += `
            <audio controls preload="auto" style="display: inline">
              <source src="${song.url}" type="${song.content_type}">
            </audio>
            <div class="font-normal text-sm">${song.title}${song.artist ? ' - ' + song.artist : ''}</div>
          `;
        }
      }
    }

    // Build multi-dance slot display
    let multiDanceHtml = '';
    if (dance.heat_length) {
      const slotDisplay = this.heatDanceSlotDisplay();
      const danceNames = this.heatMultiDanceNames();
      const callbackText = this.callbacks ? `(Callback ${this.callbacks})` : '';

      multiDanceHtml = `
        <div class="text-2xl font-normal">
          ${slotDisplay}
          ${danceNames}
          ${callbackText ? `<span>${callbackText}</span>` : ''}
        </div>
      `;
    }

    // Build heat list URL - use SPA route for offline support
    const heatlistUrl = `/scores/${judge.id}/spa?style=${this.style}`;

    this.innerHTML = `
      <h1 class="font-bold text-4xl pt-1 pb-3 text-center mx-8">
        <a href="${heatlistUrl}" rel="up">
          <span>Heat ${number}:<br class="block sm:hidden"> ${danceName}${comboDanceHtml}
      </span>
</a>${judgeBacksHtml ? '\n    ' + judgeBacksHtml : ''}${emceeHtml ? '\n    ' + emceeHtml : ''}${multiDanceHtml ? '\n    ' + multiDanceHtml : ''}
  </h1>
    `;
  }
}

customElements.define('heat-header', HeatHeader);
