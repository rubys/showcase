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
    this.judgeId = parseInt(this.getAttribute('judge-id'));
    this.scoringStyle = this.getAttribute('style') || 'radio';
    this.data = null;

    this.render();
  }

  /**
   * Set the heat data (called from parent HeatPage)
   */
  setData(data) {
    this.data = data;
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

    const { judge, event, heats } = this.data;

    // Build agenda map (category headers)
    const agenda = this.buildAgenda(heats);

    // Group heats by scoring status
    const scored = this.getScoredHeats();

    this.innerHTML = `
      <div class="mx-auto w-full md:w-2/3">
        <h1 class="font-bold text-4xl mb-4">${this.escapeHtml(judge.name)}</h1>

        <p class="mb-4">
          <strong>Event:</strong> ${this.escapeHtml(event.name)}
        </p>

        <table class="w-full">
          <tbody>
            ${heats.map(heat => this.renderHeat(heat, agenda, scored)).join('')}
          </tbody>
        </table>
      </div>
    `;
  }

  /**
   * Build agenda map - shows category name at first heat of each category
   */
  buildAgenda(heats) {
    const agenda = {};
    let lastCategory = null;

    heats.forEach(heat => {
      const category = heat.category;
      if (category !== lastCategory) {
        agenda[heat.number] = category;
        lastCategory = category;
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
    // Category header if this is first heat in category
    const categoryHeader = agenda[heat.number] ? `
      <tr>
        <td colspan="2" class="py-4 text-xl font-bold">${this.escapeHtml(agenda[heat.number])}</td>
      </tr>
    ` : '';

    // Check if heat is scored
    const isScored = scored[heat.number];
    const textColor = isScored ? 'text-slate-400' : 'text-black';

    // Build heat URL
    const url = `/scores/${this.judgeId}/spa?heat=${heat.number}&style=${this.scoringStyle}`;

    return `
      ${categoryHeader}
      <tr class="${textColor}">
        <td class="py-1">
          <a href="${url}" class="hover:underline">${heat.number}</a>
        </td>
        <td class="py-1">
          <a href="${url}" class="hover:underline">
            ${this.escapeHtml(heat.category)} ${this.escapeHtml(heat.dance.name)}
          </a>
        </td>
      </tr>
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
