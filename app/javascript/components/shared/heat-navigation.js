/**
 * HeatNavigation - Previous/next navigation footer
 *
 * Displays navigation controls for moving between heats:
 * - Previous heat button (<<)
 * - Judge information and logo
 * - Next heat button (>>)
 * - Optional judge presence checkbox (when assign_judges is enabled)
 */

export class HeatNavigation extends HTMLElement {
  connectedCallback() {
    this.render();
    this.attachEventListeners();
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
   * Toggle judge presence
   */
  togglePresence(event) {
    const checkbox = event.target;
    const isPresent = checkbox.checked;

    // Send update to server
    fetch(`/people/${this.judgeData.id}/toggle_present`, {
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

    // Always show logo (intertwingly.png)
    const logoHtml = `<a href="${this.rootPath}"><img class="absolute right-4 top-4 h-8" src="/intertwingly.png" /></a>`;

    let judgeSection = '';
    if (this.assignJudges) {
      const checked = judge.present ? 'checked' : '';
      judgeSection = `
        <h1 class="font-bold text-2xl pt-1 pb-3 flex-1 text-center">
          <input type="checkbox" name="active" ${checked} class="w-6 h-6 mr-3">
          <a href="/people/${judge.id}">${judge.name}</a>
          ${logoHtml}
        </h1>
      `;
    } else {
      judgeSection = `
        <h1 class="font-bold text-2xl pt-1 pb-3 flex-1 text-center">
          <a href="/people/${judge.id}">${judge.name}</a>
          ${logoHtml}
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
