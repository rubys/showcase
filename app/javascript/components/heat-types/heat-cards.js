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

import { heatDataManager } from 'helpers/heat_data_manager';
import { enhanceWithPersonId } from 'helpers/score_data_helper';

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

  disconnectedCallback() {
    // No event listeners to clean up (all listeners are on child elements that get removed with innerHTML)
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
  async handleDrop(event, scoreColumn) {
    event.preventDefault();
    scoreColumn.classList.remove('bg-yellow-200');

    if (!this.draggedElement) return false;

    const parent = this.draggedElement.parentElement;
    const back = this.draggedElement.querySelector('span');

    // Move card to new column
    this.draggedElement.style.opacity = '1';

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

    // Save to server (postScore handles UI updates)
    const heatId = parseInt(this.draggedElement.getAttribute('data-heat'));
    const score = scoreColumn.getAttribute('data-score') || '';

    // Build score data with person_id if category scoring enabled
    const data = enhanceWithPersonId(
      { heat: heatId, score: score },
      this.results,
      heatId,
      this.judgeData.id
    );

    const response = await this.postScore(data, this.draggedElement);

    // Revert on error
    if (!response.ok) {
      parent.appendChild(this.draggedElement);
    }

    return false;
  }

  /**
   * Handle drag end
   */
  handleDragEnd(element) {
    element.style.opacity = '';
  }

  /**
   * Post score to server (with offline support)
   */
  async postScore(data, element) {
    const back = element.querySelector('span');
    if (back) back.style.opacity = '0.5';

    try {
      // Save score (handles online/offline automatically)
      const judgeId = this.judgeData.id;
      await heatDataManager.saveScore(judgeId, data);

      // Update UI on success
      if (back) {
        back.style.opacity = '1';
        back.classList.remove('text-red-500');
      }

      const errorDiv = this.querySelector('[data-target="error"]');
      if (errorDiv) errorDiv.style.display = 'none';

      // Notify parent to update in-memory data
      this.dispatchEvent(new CustomEvent('score-updated', {
        bubbles: true,
        detail: data
      }));

      // Notify navigation to update pending count
      this.dispatchEvent(new CustomEvent('pending-count-changed', {
        bubbles: true
      }));

      return { ok: true };
    } catch (error) {
      console.error('Failed to save score:', error);

      // Update UI on error
      if (back) {
        back.style.opacity = '1';
        back.classList.add('text-red-500');
      }

      const errorDiv = this.querySelector('[data-target="error"]');
      if (errorDiv) {
        errorDiv.textContent = error.message || 'Failed to save score';
        errorDiv.style.display = 'block';
      }

      return { ok: false };
    }
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
