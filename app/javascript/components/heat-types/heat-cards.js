/**
 * HeatCards - Card-based drag-and-drop scoring interface
 *
 * Displays subjects as draggable cards organized by score.
 * Cards can be dragged between score columns to assign scores.
 *
 * Features:
 * - Draggable cards with back numbers and names
 * - Score columns (including unscored column)
 * - Visual feedback during drag operations
 * - Auto-save on drop
 * - Responsive layout (shows more info on larger screens)
 */

export class HeatCards extends HTMLElement {
  connectedCallback() {
    // Make this element display as flex row to match original layout
    this.style.display = 'flex';
    this.style.flexDirection = 'row';
    this.style.flex = '1';
    this.style.overflow = 'hidden';

    this.draggedElement = null;
    this.render();
    this.attachEventListeners();
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

  get scores() {
    return JSON.parse(this.getAttribute('scores') || '[]');
  }

  get results() {
    // Results is a map of score -> array of subjects
    return JSON.parse(this.getAttribute('results') || '{}');
  }

  get backnums() {
    return this.eventData.backnums;
  }

  get trackAges() {
    return this.eventData.track_ages;
  }

  get combineOpenAndClosed() {
    return this.eventData.heat_range_cat === 1;
  }

  /**
   * Get subject category display
   */
  getSubjectCategory(entry) {
    if (!entry.age) return '';

    const ageCategory = entry.age?.category || '';

    if (this.trackAges && ageCategory) {
      return ageCategory;
    }

    return '';
  }

  /**
   * Build a card for a subject
   */
  buildCard(subject) {
    const entry = subject;
    const lvl = entry.level?.initials || '';

    // Get column_order preference from event data
    const event = this.eventData;
    const columnOrder = event?.column_order || 1;

    // Determine name order based on column_order or professional status
    let firstBack, secondBack;
    if (columnOrder === 1 || entry.follow.type === 'Professional') {
      firstBack = entry.lead.name;
      secondBack = entry.follow.name;
    } else {
      firstBack = entry.follow.name;
      secondBack = entry.lead.name;
    }

    // Format names for display (remove commas and spaces, truncate to 7 chars)
    firstBack = firstBack.replace(/[, ]/g, '').substring(0, 7);
    secondBack = secondBack.replace(/[, ]/g, '').substring(0, 7);

    const subjectCategory = this.getSubjectCategory(entry);
    const levelInitials = entry.level?.initials || '';

    let cardContent;

    if (this.backnums && entry.lead.back) {
      // Back number mode
      cardContent = `
        <span class="my-auto">
          <span class="font-bold text-xl">${entry.lead.back}</span>
          <div class="hidden text-xs sm:block">${subjectCategory}${subjectCategory ? '-' : ''}${levelInitials}</div>
        </span>
        <div class="hidden text-sm sm:block base-${lvl}"><br>
          <span class="text-l my-auto">${firstBack} ${secondBack}</span>
        </div>
      `;
    } else {
      // Name mode
      const categoryLine = this.combineOpenAndClosed && ['Open', 'Closed'].includes(this.heatData.category)
        ? `${this.heatData.category}<br>`
        : '';

      cardContent = `
        <div class="my-auto">
          <span class="text-l my-auto">${firstBack} ${secondBack}</span>
        </div>
        <div class="hidden text-sm sm:block base-${lvl}"><br>
          ${categoryLine}
          ${subjectCategory}<br>
          ${levelInitials}
        </div>
      `;
    }

    return `
      <div class='grid align-middle w-20 my-[1%] min-h-[12%] sm:min-h-[24%] mx-1 border-2 rounded-lg text-center head-${lvl}'
           draggable="true"
           data-heat="${subject.id}"
           id="heat-${subject.id}">
        ${cardContent}
      </div>
    `;
  }

  /**
   * Build a score column
   */
  buildScoreColumn(score) {
    const subjects = this.results[score] || [];
    const isUnscored = score === '';

    const containerClass = isUnscored
      ? 'my-auto h-full max-w-[30%] min-w-[30%] border-2 border-slate-400 flex flex-col flex-wrap pl-4'
      : 'flex flex-wrap border-2 h-full pl-4';

    const cards = subjects.map(subject => this.buildCard(subject)).join('');

    return `
      <div class="${containerClass}" data-score="${score}">
        <span class="order-2 ml-auto p-2">${score}</span>
        ${cards}
      </div>
    `;
  }

  /**
   * Handle drag start
   */
  handleDragStart(event, element) {
    this.draggedElement = element;
    element.style.opacity = '0.4';

    const back = element.querySelector('span');
    if (back) {
      back.style.opacity = '0.5';
    }

    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('application/drag-id', element.id);
  }

  /**
   * Handle drag over
   */
  handleDragOver(event) {
    event.preventDefault();
    return true;
  }

  /**
   * Handle drag enter
   */
  handleDragEnter(scoreColumn) {
    scoreColumn.classList.add('bg-yellow-200');
  }

  /**
   * Handle drag leave
   */
  handleDragLeave(scoreColumn) {
    scoreColumn.classList.remove('bg-yellow-200');
  }

  /**
   * Handle drop
   */
  handleDrop(event, scoreColumn) {
    event.preventDefault();
    scoreColumn.classList.remove('bg-yellow-200');

    if (!this.draggedElement) return false;

    const parent = this.draggedElement.parentElement;
    const back = this.draggedElement.querySelector('span');

    // Move card to new column
    this.draggedElement.style.opacity = '1';
    if (back) back.style.opacity = '0.5';

    // Find insertion point (sorted by back number)
    const backText = back?.textContent || '';
    const cards = Array.from(scoreColumn.querySelectorAll('[draggable="true"]'));
    const before = cards.find(card => {
      const cardBack = card.querySelector('span')?.textContent || '';
      return cardBack >= backText;
    });

    if (before) {
      scoreColumn.insertBefore(this.draggedElement, before);
    } else {
      scoreColumn.appendChild(this.draggedElement);
    }

    // Save to server
    const heatId = parseInt(this.draggedElement.getAttribute('data-heat'));
    const score = scoreColumn.getAttribute('data-score') || '';

    this.postScore({ heat: heatId, score: score }, this.draggedElement)
      .then(response => {
        if (back) back.style.opacity = '1';

        if (response.ok) {
          if (back) back.classList.remove('text-red-500');
        } else {
          // Revert on error
          parent.appendChild(this.draggedElement);
          if (back) back.classList.add('text-red-500');
        }
      });

    return false;
  }

  /**
   * Handle drag end
   */
  handleDragEnd(element) {
    element.style.opacity = '';
  }

  /**
   * Post score to server
   */
  postScore(data, element) {
    return fetch(this.getAttribute('drop-action') || '', {
      method: 'POST',
      headers: window.inject_region({
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Content-Type': 'application/json'
      }),
      credentials: 'same-origin',
      body: JSON.stringify(data)
    }).then(response => {
      const errorDiv = this.querySelector('[data-target="error"]');

      if (response.ok) {
        if (errorDiv) errorDiv.style.display = 'none';

        // Notify parent to update in-memory data
        this.dispatchEvent(new CustomEvent('score-updated', {
          bubbles: true,
          detail: data
        }));
      } else {
        if (errorDiv) {
          errorDiv.textContent = response.statusText;
          errorDiv.style.display = 'block';
        }
      }

      return response;
    }).catch(error => {
      console.error('Failed to save score:', error);
      return { ok: false };
    });
  }

  /**
   * Attach event listeners
   */
  attachEventListeners() {
    // Draggable cards
    const cards = this.querySelectorAll('[draggable="true"]');
    cards.forEach(card => {
      card.addEventListener('dragstart', (e) => this.handleDragStart(e, card));
      card.addEventListener('dragend', () => this.handleDragEnd(card));
    });

    // Score columns (drop targets)
    const scoreColumns = this.querySelectorAll('[data-score]');
    scoreColumns.forEach(column => {
      column.addEventListener('dragover', (e) => this.handleDragOver(e));
      column.addEventListener('dragenter', () => this.handleDragEnter(column));
      column.addEventListener('dragleave', () => this.handleDragLeave(column));
      column.addEventListener('drop', (e) => this.handleDrop(e, column));
    });
  }

  render() {
    const scoreColumns = this.scores.map(score => this.buildScoreColumn(score)).join('');

    // Build unscored column (empty score value)
    const unscoredSubjects = this.results[''] || [];
    const unscoredCards = unscoredSubjects.map(subject => this.buildCard(subject)).join('');

    this.innerHTML = `
      <div class="grow flex flex-col border-2 border-slate-400">
        <div class="hidden text-red-600 text-4xl" data-target="error"></div>
        ${scoreColumns}
      </div><div class="my-auto h-full max-w-[30%] min-w-[30%] border-2 border-slate-400
         flex flex-col flex-wrap pl-4" data-score="">
        <span class="order-2 ml-auto p-2"></span>
        ${unscoredCards}
      </div>
    `;
  }
}

customElements.define('heat-cards', HeatCards);
