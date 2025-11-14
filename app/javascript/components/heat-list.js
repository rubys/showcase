/**
 * HeatList - Display list of all heats for judge selection
 *
 * Shows when navigating to /scores/:judge/spa with no heat parameter.
 * This is the "home" screen for offline scoring - works entirely from cached data.
 *
 * Usage:
 *   <heat-list judge-id="123" style="radio"></heat-list>
 */

export class HeatList extends HTMLElement {
  connectedCallback() {
    // Make this element transparent in layout - don't interfere with child layout
    const nativeStyle = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'style').get.call(this);
    nativeStyle.display = 'contents';

    this.judgeId = parseInt(this.getAttribute('judge-id'));
    this.scoringStyle = this.getAttribute('scoring-style') || 'radio';
    this.basePath = this.getAttribute('base-path') || '';
    this.data = null;
    this.sortOrder = null;  // Will be set from data
    this.showAssignments = null;  // Will be set from data
    this.infoBoxVisible = false;

    this.render();
  }

  /**
   * Set the heat data (called from parent HeatPage)
   */
  setData(data) {
    this.data = data;
    // Initialize sort order and show assignments from judge preferences
    if (data && data.judge) {
      this.sortOrder = data.judge.sort_order || 'back';
      this.showAssignments = data.judge.show_assignments || 'first';
    }
    this.render();
  }

  /**
   * Render the heat list
   */
  render() {
    if (!this.data) {
      this.innerHTML = '<div class="text-center py-8">Loading heat list...</div>';
      return;
    }

    const { judge, event, heats, qr_code, assign_judges } = this.data;

    // Build agenda map (category headers)
    const agenda = this.buildAgenda(heats);

    // Group heats by scoring status
    const scored = this.getScoredHeats();

    this.innerHTML = `
      <div class="mx-auto w-full md:w-2/3">
        ${this.renderInfoBox()}

        <div class="float-right w-60">
          ${qr_code ? this.renderQRCode(qr_code) : ''}
          ${this.renderSortOrder()}
          ${assign_judges ? this.renderShowAssignments() : ''}
        </div>

        ${this.renderUnassignedWarning()}

        <table>
          <tbody>
            ${heats.map(heat => this.renderHeat(heat, agenda, scored)).join('')}
          </tbody>
        </table>
      </div>
    `;

    // Attach event listeners after render
    this.attachEventListeners();
  }

  /**
   * Render info box with toggle button
   */
  renderInfoBox() {
    const displayStyle = this.infoBoxVisible || !this.getScoredHeats()[Object.keys(this.getScoredHeats())[0]] ? 'block' : 'none';

    return `
      <div class="info-box-container">
        <div class="info-button">&#x24D8;</div>
        <ul class="info-box" style="display: ${displayStyle}">
          <li>Be sure to do a dry run before the event.</li>
          <li>This is the experimental offline-capable scoring interface. It works offline and syncs when you reconnect.</li>
          <li>Scores are saved automatically to your device and uploaded when connectivity is available.</li>
          <li>Even if you are planning on having judges enter scores in realtime during the application, it is best to print out paper copies in case of application or network failures.</li>
        </ul>
      </div>
    `;
  }

  /**
   * Render QR code
   */
  renderQRCode(qr_code) {
    return `
      <div title="${this.escapeHtml(qr_code.url)}">
        ${qr_code.svg}
      </div>
    `;
  }

  /**
   * Render sort order selection
   */
  renderSortOrder() {
    return `
      <h2 class="mt-12 font-bold text-2xl">Sort order</h2>
      <div class="sort-order-form">
        <div>
          <input type="radio" name="sort" value="back" ${this.sortOrder === 'back' ? 'checked' : ''}>
          <span>Back Number</span>
        </div>
        <div>
          <input type="radio" name="sort" value="level" ${this.sortOrder === 'level' ? 'checked' : ''}>
          <span>Level</span>
        </div>
      </div>
    `;
  }

  /**
   * Render show assignments selection
   */
  renderShowAssignments() {
    return `
      <h2 class="mt-12 font-bold text-2xl">Show assignments</h2>
      <div class="show-assignments-form">
        <div>
          <input type="radio" name="show" value="first" ${this.showAssignments === 'first' ? 'checked' : ''}>
          <span>First</span>
        </div>
        <div>
          <input type="radio" name="show" value="only" ${this.showAssignments === 'only' ? 'checked' : ''}>
          <span>Only</span>
        </div>
        <div>
          <input type="radio" name="show" value="mixed" ${this.showAssignments === 'mixed' ? 'checked' : ''}>
          <span>In Sort Order</span>
        </div>
      </div>
    `;
  }

  /**
   * Attach event listeners for interactive elements
   */
  attachEventListeners() {
    // Info box toggle
    const infoButton = this.querySelector('.info-button');
    const infoBox = this.querySelector('.info-box');
    if (infoButton && infoBox) {
      infoButton.addEventListener('click', () => {
        this.infoBoxVisible = !this.infoBoxVisible;
        infoBox.style.display = this.infoBoxVisible ? 'block' : 'none';
      });
    }

    // Sort order change
    const sortRadios = this.querySelectorAll('input[name="sort"]');
    sortRadios.forEach(radio => {
      radio.addEventListener('change', (e) => {
        this.sortOrder = e.target.value;
        this.saveSortOrder(e.target.value);
        // Re-render to apply new sort
        this.render();
      });
    });

    // Show assignments change
    const showRadios = this.querySelectorAll('input[name="show"]');
    showRadios.forEach(radio => {
      radio.addEventListener('change', (e) => {
        this.showAssignments = e.target.value;
        this.saveShowAssignments(e.target.value);
        // Re-render to apply new filter
        this.render();
      });
    });
  }

  /**
   * Save sort order preference to server
   */
  async saveSortOrder(sortOrder) {
    try {
      const formData = new FormData();
      formData.append('sort', sortOrder);
      formData.append('show', this.showAssignments);
      formData.append('style', this.scoringStyle);

      await fetch(`${this.basePath}/scores/sort`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
        }
      });
    } catch (error) {
      console.error('Failed to save sort order:', error);
    }
  }

  /**
   * Save show assignments preference to server
   */
  async saveShowAssignments(showAssignments) {
    try {
      const formData = new FormData();
      formData.append('show', showAssignments);
      formData.append('style', this.scoringStyle);
      formData.append('sort', this.sortOrder);

      await fetch(`${this.basePath}/people/${this.judgeId}/show_assignments`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
        }
      });
    } catch (error) {
      console.error('Failed to save show assignments:', error);
    }
  }

  /**
   * Render unassigned couples warning
   */
  renderUnassignedWarning() {
    const unassigned = this.getUnassignedHeats();
    if (unassigned.length === 0) return '';

    return `
      <p class="mt-4 text-red-500">Unassigned couples in heats: ${unassigned.join(', ')}</p>
    `;
  }

  /**
   * Get list of heat numbers with unassigned couples
   */
  getUnassignedHeats() {
    if (!this.data) return [];

    const unassigned = [];
    const judgeId = this.data.judge.id;

    this.data.heats.forEach(heat => {
      // Check if any subject has a score record for this judge
      // (When assign_judges > 0, empty score records indicate assignment)
      const hasAssignment = heat.subjects.some(subject =>
        subject.scores?.some(s => s.judge_id === judgeId)
      );

      // If assign_judges is enabled and there's no assignment, mark as unassigned
      if (this.data.assign_judges && !hasAssignment) {
        unassigned.push(heat.number);
      }
    });

    return unassigned;
  }

  /**
   * Build agenda map - shows category name at first heat of each category
   */
  buildAgenda(heats) {
    const agenda = {};
    let lastCategory = null;

    heats.forEach(heat => {
      const categoryName = heat.dance.category_name || heat.category;
      if (categoryName !== lastCategory) {
        agenda[heat.number] = categoryName;
        lastCategory = categoryName;
      }
    });

    return agenda;
  }

  /**
   * Get map of heat numbers that have been scored
   */
  getScoredHeats() {
    if (!this.data) return {};

    const scored = {};
    const judgeId = this.data.judge.id;

    this.data.heats.forEach(heat => {
      let allScored = true;

      heat.subjects.forEach(subject => {
        const score = subject.scores?.find(s => s.judge_id === judgeId);
        if (!score || (!score.value && !score.comments && !score.good && !score.bad)) {
          allScored = false;
        }
      });

      if (allScored && heat.subjects.length > 0) {
        scored[heat.number] = true;
      }
    });

    return scored;
  }

  /**
   * Render a single heat row
   */
  renderHeat(heat, agenda, scored) {
    const unassigned = this.getUnassignedHeats();
    const isUnassigned = unassigned.includes(heat.number);

    // Category header if this is first heat in category
    const categoryHeader = agenda[heat.number] ? `
      <tr class="${isUnassigned ? 'text-red-500' : ''}">
        <td colspan="2" class="py-4 text-xl">${this.escapeHtml(agenda[heat.number])}</td>
      </tr>
    ` : '';

    // Check if heat is scored
    const isScored = scored[heat.number];

    // Determine text color: red for unassigned, gray for scored, black otherwise
    let textColor;
    if (isUnassigned) {
      textColor = 'text-red-500';
    } else if (isScored) {
      textColor = 'text-slate-400';
    } else {
      textColor = 'text-black';
    }

    // Build heat URL (include base-path for scoped routes)
    const url = `${this.basePath}/scores/${this.judgeId}/spa?heat=${heat.number}&style=${this.scoringStyle}`;

    return `
      ${categoryHeader}
      <tr class="${textColor}">
        <td><a href="${url}">${heat.number}</a>
        </td><td><a href="${url}">${this.escapeHtml(heat.category)} ${this.escapeHtml(heat.dance.name)}</a>
      </td></tr>
    `;
  }

  /**
   * Escape HTML to prevent XSS
   */
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
}

// Register the custom element
customElements.define('heat-list', HeatList);
