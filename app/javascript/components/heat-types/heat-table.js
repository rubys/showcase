/**
 * HeatTable - Tabular heat display for Open/Closed heats
 *
 * Supports multiple scoring modes:
 * - Radio buttons (default) - Click to select score
 * - Numeric input (#) - Enter 2-digit score
 * - Checkboxes (semi-finals) - Callback selection
 * - Feedback buttons (+, &, @) - Good/bad feedback
 * - Comments (if enabled)
 *
 * This is the most complex heat type as it handles all the different
 * scoring modes and layouts used in ballroom competitions.
 */

import { heatDataManager } from 'helpers/heat_data_manager';
import FeedbackPanel from 'components/shared/feedback-panel';

export class HeatTable extends HTMLElement {
  connectedCallback() {
    // Make this element participate in flex layout
    // Access the native style property via the prototype to avoid getter conflict
    const nativeStyle = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'style').get.call(this);
    nativeStyle.display = 'flex';
    nativeStyle.flexDirection = 'column';
    nativeStyle.flex = '1';
    nativeStyle.minHeight = '0';

    this.render();
    this.attachEventListeners();
  }

  disconnectedCallback() {
    // Clean up event listeners
    if (this.keydownHandler) {
      document.body.removeEventListener('keydown', this.keydownHandler);
    }
    if (this.touchStartHandler) {
      document.body.removeEventListener('touchstart', this.touchStartHandler);
      document.body.removeEventListener('touchend', this.touchEndHandler);
    }
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

  get scoring() {
    return this.getAttribute('scoring') || '';
  }

  get scores() {
    return JSON.parse(this.getAttribute('scores') || '[]');
  }

  get feedbacks() {
    return JSON.parse(this.getAttribute('feedbacks') || '[]');
  }

  get ballrooms() {
    return JSON.parse(this.getAttribute('ballrooms') || '{}');
  }

  get assignJudges() {
    return this.getAttribute('assign-judges') === 'true';
  }

  get combineOpenAndClosed() {
    return this.eventData.heat_range_cat === 1;
  }

  get trackAges() {
    return this.eventData.track_ages;
  }

  /**
   * Get subject category display
   */
  getSubjectCategory(entry) {
    if (entry.pro) return 'Pro';

    const ageCategory = entry.age?.category || '';
    const levelInitials = entry.level?.initials || '';

    if (this.trackAges && ageCategory) {
      return `${ageCategory} - ${levelInitials}`;
    }

    return levelInitials;
  }

  /**
   * Get existing score for a subject
   */
  getSubjectScore(subject) {
    if (!subject.scores) return null;
    return subject.scores.find(s => s.judge_id === this.judgeData.id);
  }

  /**
   * Build table headers
   */
  buildHeaders() {
    const ballroomsCount = this.heatData.dance.ballrooms || this.eventData.ballrooms;
    const columnOrder = this.judgeData.column_order !== undefined ? this.judgeData.column_order : 1;
    const leadHeader = columnOrder === 1 ? 'Lead' : 'Student';
    const followHeader = columnOrder === 1 ? 'Follow' : 'Instructor';

    let scoreHeaders = '';

    if (this.style !== 'emcee') {
      if (this.scoring === '#') {
        scoreHeaders = '<th class="text-center border-b-2 border-black">Score</th>';
      } else if (this.heatData.dance.uses_scrutineering && this.scores.length > 0) {
        const colCount = this.scores.length;
        scoreHeaders = `<th class="text-center" colspan="${colCount}">Callback?</th></tr><tr>`;
        this.scores.forEach(() => {
          scoreHeaders += '<th class="border-b-2 border-black"></th>';
        });
      } else if (!['&', '+', '@'].includes(this.scoring)) {
        const colCount = this.scores.length;
        scoreHeaders = `<th class="text-center" colspan="${colCount}">Score</th></tr><tr>`;
        this.scores.forEach(score => {
          const label = score === '' ? '-' : score;
          scoreHeaders += `<th class="border-b-2 border-black">${label}</th>`;
        });
      }
    }

    return `
      <thead>
        <tr>
          <th class="text-left border-b-2 border-black" rowspan="2">Back</th>
          ${ballroomsCount > 1 ? '<th class="text-left border-b-2 border-black" rowspan="2">Ballroom</th>' : ''}
          <th class="text-left border-b-2 border-black" rowspan="2">${leadHeader}</th>
          <th class="text-left border-b-2 border-black" rowspan="2">${followHeader}</th>
          <th class="text-left border-b-2 border-black" rowspan="2">Category</th>
          <th class="text-left border-b-2 border-black" rowspan="2">Studio</th>
          ${scoreHeaders}
        </tr>
      </thead>
    `;
  }

  /**
   * Build scoring cells for a subject
   */
  buildScoringCells(subject) {
    if (this.style === 'emcee') return '';

    const score = this.getSubjectScore(subject);
    const scoreValue = score?.value || '';

    if (this.scoring === '#') {
      // Numeric input
      return `
        <td><div class="mx-auto text-center">
          <input class="text-center w-20 h-10 border-2 invalid:border-red-600"
            pattern="^\\d\\d$" name="${subject.id}" value="${scoreValue}">
        </div></td>
      `;
    } else if (this.heatData.dance.uses_scrutineering) {
      // Callback checkbox
      const checked = scoreValue ? 'checked' : '';
      return `<td class="text-center"><input type="checkbox" name="${subject.id}" value="1" ${checked}></td>`;
    } else if (!['&', '+', '@'].includes(this.scoring)) {
      // Radio buttons
      return this.scores.map(scoreOption => {
        const checked = scoreValue === scoreOption ? 'checked' : '';
        return `<td class="text-center"><input type="radio" name="${subject.id}" value="${scoreOption}" ${checked}></td>`;
      }).join('');
    }

    return '';
  }

  /**
   * Build feedback row for a subject
   */
  buildFeedbackRow(subject, colSpan) {
    if (this.style === 'emcee' || ['1', 'G', '#'].includes(this.scoring)) {
      return '';
    }

    const score = this.getSubjectScore(subject);
    const good = (score?.good || '').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
    const bad = (score?.bad || '').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
    const value = (score?.value || '').replace(/"/g, '&quot;').replace(/'/g, '&apos;');

    // Determine overall options based on scoring type
    let overallOptions = [];
    if (this.scoring === '&') {
      overallOptions = ['1', '2', '3', '4', '5'];
    } else if (this.scoring === '@') {
      overallOptions = ['B', 'S', 'G', 'GH'];
    }

    // Determine good/bad feedback options
    let goodOptions = [];
    let badOptions = [];

    if (this.feedbacks.length > 0) {
      // Custom feedbacks from database
      goodOptions = this.feedbacks.map(f => ({ abbr: f.abbr, full: f.value }));
      badOptions = this.feedbacks.map(f => ({ abbr: f.abbr, full: f.value }));
    } else if (this.scoring === '&' || this.scoring === '@') {
      // Default feedback for & and @
      const defaultFeedbacks = [
        { abbr: 'F', full: 'Frame' },
        { abbr: 'P', full: 'Posture' },
        { abbr: 'FW', full: 'Footwork' },
        { abbr: 'LF', full: 'Lead/\u200BFollow' },
        { abbr: 'T', full: 'Timing' },
        { abbr: 'S', full: 'Styling' }
      ];
      goodOptions = defaultFeedbacks;
      badOptions = defaultFeedbacks;
    } else if (this.scoring === '+') {
      // Detailed feedback for +
      const detailedFeedbacks = [
        { abbr: 'DF', full: 'Dance Frame' },
        { abbr: 'T', full: 'Timing' },
        { abbr: 'LF', full: 'Lead/\u200BFollow' },
        { abbr: 'CM', full: 'Cuban Motion' },
        { abbr: 'RF', full: 'Rise & Fall' },
        { abbr: 'FW', full: 'Footwork' },
        { abbr: 'B', full: 'Balance' },
        { abbr: 'AS', full: 'Arm Styling' },
        { abbr: 'CB', full: 'Contra-Body' },
        { abbr: 'FC', full: 'Floor Craft' }
      ];
      goodOptions = detailedFeedbacks;
      badOptions = detailedFeedbacks;
    }

    // If no feedback options, return empty
    if (overallOptions.length === 0 && goodOptions.length === 0 && badOptions.length === 0) {
      return '';
    }

    // Use FeedbackPanel component
    const slot = this.getAttribute('slot') || '';
    return `
      <tr class="open-fb-row" data-heat="${subject.id}">
        <td colspan="${colSpan}">
          <feedback-panel
            judge-id="${this.judgeData.id}"
            heat="${subject.id}"
            slot="${slot}"
            good="${good}"
            bad="${bad}"
            value="${value}"
            overall-options='${JSON.stringify(overallOptions)}'
            good-options='${JSON.stringify(goodOptions)}'
            bad-options='${JSON.stringify(badOptions)}'>
          </feedback-panel>
        </td>
      </tr>
    `;
  }

  /**
   * Build comments row for a subject
   */
  buildCommentsRow(subject, colSpan) {
    if (!this.eventData.judge_comments || this.style === 'emcee') {
      return '';
    }

    const score = this.getSubjectScore(subject);
    const comments = score?.comments || '';

    return `
      <tr>
        <td></td>
        <td colspan="${colSpan - 1}">
          <textarea data-heat="${subject.id}"
            class="resize-none block p-2.5 w-full text-sm text-gray-900 bg-gray-50 rounded-lg border border-gray-300 focus:ring-blue-500 focus:border-blue-500"
          >${comments}</textarea>
        </td>
      </tr>
    `;
  }

  /**
   * Build table rows for all subjects
   */
  buildRows() {
    const ballroomsCount = this.heatData.dance.ballrooms || this.eventData.ballrooms;
    const columnOrder = this.judgeData.column_order !== undefined ? this.judgeData.column_order : 1;
    const ballroomsData = this.ballrooms;
    const colSpan = 5 + (ballroomsCount > 1 ? 1 : 0) + (this.scores?.length || 0);

    let rowsHtml = '';
    let lastCat = null;
    let lastAssign = false;
    let lastDance = null;

    Object.entries(ballroomsData).forEach(([ballroom, subjects]) => {
      if (subjects.length === 0) return;

      // Ballroom separator
      if (ballroom === 'B') {
        rowsHtml += `<tr><td colspan="${colSpan}" class="bg-black"></td></tr>`;
      }

      subjects.forEach(subject => {
        const assign = this.assignJudges
          ? subject.scores?.some(s => s.judge_id === this.judgeData.id)
          : true;

        // Skip if showing only assigned and not assigned
        if (this.judgeData.show_assignments === 'only' && !assign) return;

        // Dance separator
        if (lastDance && subject.dance_id !== lastDance) {
          rowsHtml += `<tr><td colspan="${colSpan}" class="bg-gray-400"></td></tr>`;
        }
        lastDance = subject.dance_id;

        const subcat = this.getSubjectCategory(subject);

        // Category/assignment spacing
        if ((this.judgeData.sort_order === 'level' && lastCat && subcat !== lastCat) ||
            (this.assignJudges && assign !== lastAssign && lastCat)) {
          const height = this.eventData.judge_comments ? 'h-12' : (this.judgeData.sort_order === 'level' ? 'h-6' : 'h-4');
          rowsHtml += `<tr><td class="${height}"></td></tr>`;
        }
        lastCat = subcat;
        lastAssign = assign;

        // Determine names order
        let firstName, secondName;
        if (columnOrder === 1 || subject.lead.type === 'Student') {
          firstName = subject.lead.display_name || subject.lead.name;
          secondName = subject.follow.display_name || subject.follow.name;
        } else {
          firstName = subject.follow.display_name || subject.follow.name;
          secondName = subject.lead.display_name || subject.lead.name;
        }

        // Category display
        let categoryDisplay = subcat;
        if (this.combineOpenAndClosed && ['Open', 'Closed'].includes(this.heatData.category)) {
          categoryDisplay = `${this.heatData.category} - ${subcat}`;
        }

        // Back number with assignment highlighting
        let backCell;
        if (this.assignJudges && assign && this.judgeData.show_assignments !== 'only') {
          const back = subject.lead.back || '&#9733;';
          backCell = `<td class="${this.judgeData.sort_order !== 'level' ? 'py-2 ' : ''}font-bold text-xl"><span class="border-2 border-red-600 px-2 rounded-full">${back}</span></td>`;
        } else {
          backCell = `<td class="${this.judgeData.sort_order !== 'level' ? 'py-2 ' : ''}text-xl">${subject.lead.back}</td>`;
        }

        const isScratched = subject.number <= 0;
        const trClass = isScratched ? 'hover:bg-yellow-200 line-through opacity-50' : 'hover:bg-yellow-200';

        rowsHtml += `
          <tr class="${trClass}" id="heat-${subject.id}">
            ${backCell}
            ${ballroomsCount > 1 ? `<td class="${this.judgeData.sort_order !== 'level' ? 'py-2 ' : ''}text-center font-medium">${ballroom || '-'}</td>` : ''}
            <td>${firstName}</td>
            <td>${secondName}</td>
            <td>${categoryDisplay}</td>
            <td>${subject.studio || ''}</td>
            ${this.buildScoringCells(subject)}
          </tr>
          ${this.buildFeedbackRow(subject, colSpan)}
          ${this.buildCommentsRow(subject, colSpan)}
        `;
      });
    });

    return rowsHtml;
  }

  /**
   * Handle score change events
   */
  handleScoreChange(event) {
    const input = event.target;
    const heatId = parseInt(input.getAttribute('name'));
    const value = input.type === 'checkbox' ? (input.checked ? '1' : '') : input.value;

    this.postScore({ heat: heatId, score: value }, input);
  }

  /**
   * Handle feedback score events from open-feedback controller
   */
  handleFeedbackScore(event) {
    const { feedback, button, element } = event.detail;

    // Update UI immediately (optimistic update)
    const sections = element.children[0].children; // Get all sections (Overall, Good, Bad)
    const feedbackType = Object.keys(feedback).find(k => ['value', 'good', 'bad'].includes(k));
    const feedbackValue = feedback[feedbackType];

    // For "value" type (overall score), only one can be selected (radio behavior)
    if (feedbackType === "value") {
      for (let section of sections) {
        if (section.classList.contains("value")) {
          section.dataset.value = feedbackValue;
          for (let btn of section.querySelectorAll("button")) {
            if (btn === button) {
              btn.classList.add("selected");
            } else {
              btn.classList.remove("selected");
            }
          }
        }
      }
    } else {
      // For good/bad, toggle the selection and remove from opposite
      for (let section of sections) {
        let sectionType = section.classList.contains("good") ? "good" :
          (section.classList.contains("bad") ? "bad" : "value");

        if (sectionType === "value") continue;

        let currentFeedback = (section.dataset.value || "").split(" ").filter(f => f);

        if (sectionType === feedbackType) {
          // Same type - toggle
          const index = currentFeedback.indexOf(feedbackValue);
          if (index > -1) {
            currentFeedback.splice(index, 1);
          } else {
            currentFeedback.push(feedbackValue);
          }
        } else {
          // Opposite type - remove if present
          const index = currentFeedback.indexOf(feedbackValue);
          if (index > -1) {
            currentFeedback.splice(index, 1);
          }
        }

        section.dataset.value = currentFeedback.join(" ");

        // Update button selected states
        for (let btn of section.querySelectorAll("button")) {
          const btnValue = btn.querySelector("abbr").textContent;
          if (currentFeedback.includes(btnValue)) {
            btn.classList.add("selected");
          } else {
            btn.classList.remove("selected");
          }
        }
      }
    }

    // Save the score
    this.postScore(feedback, button);
  }

  /**
   * Handle comments change
   */
  handleCommentsChange(event) {
    const textarea = event.target;
    const heatId = parseInt(textarea.getAttribute('data-heat'));

    textarea.classList.remove('bg-gray-50');
    textarea.classList.add('bg-yellow-200');

    if (this.commentTimeout) clearTimeout(this.commentTimeout);

    this.commentTimeout = setTimeout(() => {
      this.postScore({ heat: heatId, comments: textarea.value }, textarea);
      this.commentTimeout = null;
    }, 2000);
  }

  /**
   * Post score to server (with offline support)
   */
  async postScore(data, element) {
    element.disabled = true;

    try {
      // Get data manager instance from parent heat-page
      const dataManager = this.closest('heat-page')?.dataManager;
      if (!dataManager) {
        throw new Error('HeatDataManager not available');
      }

      // Save score (handles online/offline automatically)
      const judgeId = this.judgeData.id;
      await dataManager.saveScore(judgeId, data);

      // Update UI on success
      element.disabled = false;
      if (element.tagName === 'TEXTAREA') {
        element.classList.add('bg-gray-50');
        element.classList.remove('bg-yellow-200');
      } else {
        element.style.backgroundColor = null;
      }

      // Notify parent to update in-memory data and pending count
      this.dispatchEvent(new CustomEvent('score-updated', {
        bubbles: true,
        detail: data
      }));

      // Notify navigation to update pending count
      console.debug('[heat-table] Dispatching pending-count-changed event');
      this.dispatchEvent(new CustomEvent('pending-count-changed', {
        bubbles: true
      }));
    } catch (error) {
      element.disabled = false;
      element.style.backgroundColor = '#F00';
      console.error('Failed to save score:', error);
    }
  }

  /**
   * Setup keyboard navigation listeners
   * Handles: Arrow up/down (table navigation), Tab (input focus), Escape (blur)
   * Note: Arrow left/right for heat navigation is handled by heat-page component
   */
  setupKeyboardListeners() {
    this.keydownHandler = (event) => {
      const isFormElement = ['INPUT', 'TEXTAREA'].includes(event.target.nodeName) ||
        ['INPUT', 'TEXTAREA'].includes(document.activeElement?.nodeName);

      // Arrow up/down within table (not handled - native browser behavior is fine)
      // Tab for navigation (native behavior)
      // Escape to blur
      if (event.key === 'Escape') {
        if (document.activeElement) document.activeElement.blur();
      }
      // Space/Enter for start heat button (not in table view typically)
    };

    document.body.addEventListener('keydown', this.keydownHandler);
  }

  /**
   * Setup touch gesture listeners
   * Note: Swipe left/right for heat navigation is handled by heat-page component
   * This only handles up swipe to show heat list
   */
  setupTouchListeners() {
    this.touchStart = null;

    this.touchStartHandler = (event) => {
      this.touchStart = event.touches[0];
    };

    this.touchEndHandler = (event) => {
      const direction = this.swipe(event);
      if (direction === 'up') {
        // Dispatch event for heat-page to handle
        this.dispatchEvent(new CustomEvent('show-heat-list', { bubbles: true }));
      }
    };

    document.body.addEventListener('touchstart', this.touchStartHandler);
    document.body.addEventListener('touchend', this.touchEndHandler);
  }

  /**
   * Detect swipe direction
   */
  swipe(event) {
    if (!this.touchStart) return null;
    const stop = event.changedTouches[0];
    if (stop.identifier !== this.touchStart.identifier) return null;

    const deltaX = stop.clientX - this.touchStart.clientX;
    const deltaY = stop.clientY - this.touchStart.clientY;
    const height = document.documentElement.clientHeight;
    const width = document.documentElement.clientWidth;

    if (Math.abs(deltaX) > width/2 && Math.abs(deltaY) < height/4) {
      return deltaX > 0 ? 'right' : 'left';
    } else if (Math.abs(deltaY) > height/2 && Math.abs(deltaX) < width/4) {
      return deltaY > 0 ? 'down' : 'up';
    }
    return null;
  }

  /**
   * Setup feedback row hover effects
   * Highlights the previous row when hovering over feedback row
   */
  setupFeedbackListeners() {
    const feedbackRows = this.querySelectorAll('.open-fb-row');

    for (const row of feedbackRows) {
      // Highlight previous row on hover
      const previous = row.previousElementSibling;
      if (previous) {
        row.addEventListener('mouseenter', () => {
          previous.classList.add('bg-yellow-200');
        });
        row.addEventListener('mouseleave', () => {
          previous.classList.remove('bg-yellow-200');
        });
      }
    }
  }

  /**
   * Attach event listeners
   */
  attachEventListeners() {
    // Setup keyboard navigation (arrow keys, tab, escape)
    this.setupKeyboardListeners();

    // Setup touch gestures
    this.setupTouchListeners();

    // Radio buttons and checkboxes and numeric inputs
    const scoreInputs = this.querySelectorAll('input[type="radio"], input[type="checkbox"], input[pattern]');
    scoreInputs.forEach(input => {
      input.addEventListener('change', (e) => this.handleScoreChange(e));
    });

    // Comments textareas
    const commentTextareas = this.querySelectorAll('textarea[data-heat]');
    commentTextareas.forEach(textarea => {
      textarea.addEventListener('input', (e) => this.handleCommentsChange(e));
    });

    // Setup feedback buttons (was handled by open-feedback controller)
    this.setupFeedbackListeners();
  }

  render() {
    // Get slot if this is a multi-dance heat
    const slot = this.getAttribute('slot') || '';
    const slotAttr = slot ? ` data-slot="${slot}"` : '';

    this.innerHTML = `
      <div${slotAttr} class="grow flex flex-col border-2 border-slate-400 overflow-y-auto">
        <div class="hidden text-red-600 text-4xl"></div>
        <table class="table-auto border-separate border-spacing-y-1 mx-4">
          ${this.buildHeaders()}
          <tbody>
            ${this.buildRows()}
          </tbody>
        </table>
      </div>
    `;
  }
}

customElements.define('heat-table', HeatTable);
