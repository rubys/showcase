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
    return this.getAttribute('style') || 'radio';
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
    const columnOrder = this.judgeData.column_order || 1;
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
          <input data-target="score" class="text-center w-20 h-10 border-2 invalid:border-red-600"
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
    const good = score?.good || '';
    const bad = score?.bad || '';
    const value = score?.value || '';

    let feedbackHtml = '';

    // Overall scoring buttons (& or @)
    if (this.scoring === '&') {
      feedbackHtml += `
        <div class="grid value w-full" data-value="${value}" style="grid-template-columns: 100px repeat(5, 1fr)">
          <div class="bg-gray-200 inline-flex justify-center items-center">Overall</div>
          ${[1, 2, 3, 4, 5].map(i => `<button class="open-fb" data-value="${i}"><abbr>${i}</abbr><span>${i}</span></button>`).join('')}
        </div>
      `;
    } else if (this.scoring === '@') {
      feedbackHtml += `
        <div class="grid value w-full" data-value="${value}" style="grid-template-columns: 100px repeat(4, 1fr)">
          <div class="bg-gray-200 inline-flex justify-center items-center">Overall</div>
          ${['B', 'S', 'G', 'GH'].map(v => `<button class="open-fb" data-value="${v}"><abbr>${v}</abbr><span>${v}</span></button>`).join('')}
        </div>
      `;
    }

    // Good/Bad feedback buttons
    if (this.feedbacks.length > 0) {
      // Custom feedbacks from database
      const maxOrder = Math.max(...this.feedbacks.map(f => f.order || 1));
      const goodButtons = [];
      const badButtons = [];

      for (let i = 1; i <= maxOrder; i++) {
        const feedback = this.feedbacks.find(f => (f.order || 1) === i);
        if (feedback) {
          goodButtons.push(`<button class="open-fb" data-feedback="${feedback.id}"><abbr>${feedback.abbr}</abbr><span>${feedback.value}</span></button>`);
          badButtons.push(`<button class="open-fb" data-feedback="${feedback.id}"><abbr>${feedback.abbr}</abbr><span>${feedback.value}</span></button>`);
        } else {
          goodButtons.push('<span></span>');
          badButtons.push('<span></span>');
        }
      }

      feedbackHtml += `
        <div class="grid grid-cols-2 w-full divide-x-2 divide-black">
          <div class="grid grid-cols-5 good" data-value="${good}" title="Good Job With">
            ${goodButtons.join('')}
          </div>
          <div class="grid grid-cols-5 bad" data-value="${bad}" title="Needs Work On">
            ${badButtons.join('')}
          </div>
        </div>
      `;
    } else if (this.scoring === '&' || this.scoring === '@') {
      // Default feedback for & and @
      const defaultFeedbacks = [
        { abbr: 'F', label: 'Frame' },
        { abbr: 'P', label: 'Posture' },
        { abbr: 'FW', label: 'Footwork' },
        { abbr: 'LF', label: 'Lead/\u200BFollow' },
        { abbr: 'T', label: 'Timing' },
        { abbr: 'S', label: 'Styling' }
      ];

      feedbackHtml += `
        <div class="grid good" data-value="${good}" style="grid-template-columns: 100px repeat(6, 1fr)">
          <div class="bg-gray-200 inline-flex justify-center items-center">Good</div>
          ${defaultFeedbacks.map(f => `<button class="open-fb" data-feedback="${f.abbr}"><abbr>${f.abbr}</abbr><span>${f.label}</span></button>`).join('')}
        </div>
        <div class="grid bad" data-value="${bad}" style="grid-template-columns: 100px repeat(6, 1fr)">
          <div class="bg-gray-200 inline-flex justify-center items-center">Needs Work</div>
          ${defaultFeedbacks.map(f => `<button class="open-fb" data-feedback="${f.abbr}"><abbr>${f.abbr}</abbr><span>${f.label}</span></button>`).join('')}
        </div>
      `;
    } else if (this.scoring === '+') {
      // Detailed feedback for +
      const detailedFeedbacks = [
        { abbr: 'DF', label: 'Dance Frame' },
        { abbr: 'T', label: 'Timing' },
        { abbr: 'LF', label: 'Lead/\u200BFollow' },
        { abbr: 'CM', label: 'Cuban Motion' },
        { abbr: 'RF', label: 'Rise & Fall' },
        { abbr: 'FW', label: 'Footwork' },
        { abbr: 'B', label: 'Balance' },
        { abbr: 'AS', label: 'Arm Styling' },
        { abbr: 'CB', label: 'Contra-Body' },
        { abbr: 'FC', label: 'Floor Craft' }
      ];

      feedbackHtml += `
        <div class="grid grid-cols-2 w-full divide-x-2 divide-black">
          <div class="grid grid-cols-5 good" data-value="${good}" title="Good Job With">
            ${detailedFeedbacks.map(f => `<button class="open-fb" data-feedback="${f.abbr}"><abbr>${f.abbr}</abbr><span>${f.label}</span></button>`).join('')}
          </div>
          <div class="grid grid-cols-5 bad" data-value="${bad}" title="Needs Work On">
            ${detailedFeedbacks.map(f => `<button class="open-fb" data-feedback="${f.abbr}"><abbr>${f.abbr}</abbr><span>${f.label}</span></button>`).join('')}
          </div>
        </div>
      `;
    }

    if (!feedbackHtml) return '';

    return `
      <tr data-controller="open-feedback" class="open-fb-row" data-heat="${subject.id}">
        <td colspan="${colSpan}">
          ${feedbackHtml}
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
          <textarea data-target="comments" data-heat="${subject.id}"
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
    const columnOrder = this.judgeData.column_order || 1;
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
          firstName = subject.lead.name || subject.lead.display_name;
          secondName = subject.follow.name || subject.follow.display_name;
        } else {
          firstName = subject.follow.name || subject.follow.display_name;
          secondName = subject.lead.name || subject.lead.display_name;
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
   * Post score to server
   */
  postScore(data, element) {
    element.disabled = true;

    fetch(this.getAttribute('drop-action') || '', {
      method: 'POST',
      headers: window.inject_region({
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Content-Type': 'application/json'
      }),
      credentials: 'same-origin',
      body: JSON.stringify(data)
    }).then(response => {
      element.disabled = false;

      if (response.ok) {
        if (element.tagName === 'TEXTAREA') {
          element.classList.add('bg-gray-50');
          element.classList.remove('bg-yellow-200');
        } else {
          element.style.backgroundColor = null;
        }

        // Notify parent to update in-memory data
        this.dispatchEvent(new CustomEvent('score-updated', {
          bubbles: true,
          detail: data
        }));
      } else {
        element.style.backgroundColor = '#F00';
      }
    }).catch(error => {
      element.disabled = false;
      element.style.backgroundColor = '#F00';
      console.error('Failed to save score:', error);
    });
  }

  /**
   * Attach event listeners
   */
  attachEventListeners() {
    // Radio buttons and checkboxes
    const scoreInputs = this.querySelectorAll('input[type="radio"], input[type="checkbox"], input[data-target="score"]');
    scoreInputs.forEach(input => {
      input.addEventListener('change', (e) => this.handleScoreChange(e));
    });

    // Comments textareas
    const commentTextareas = this.querySelectorAll('textarea[data-target="comments"]');
    commentTextareas.forEach(textarea => {
      textarea.addEventListener('input', (e) => this.handleCommentsChange(e));
    });

    // Feedback buttons will be handled by a separate controller
    // (open-feedback controller) which we'll need to port as well
  }

  render() {
    this.innerHTML = `
      <div class="grow flex flex-col border-2 border-slate-400 overflow-y-auto">
        <div class="hidden text-red-600 text-4xl" data-target="error"></div>
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
