/**
 * HeatSolo - Solo heat rendering with formations and scoring
 *
 * Renders a solo heat with:
 * - Dancer names and formations
 * - Studio and level information
 * - Comments textarea
 * - Score input (single or 4-part scoring)
 * - Song/artist information (for emcee)
 * - Start heat button (for emcee)
 */

export class HeatSolo extends HTMLElement {
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
    return this.getAttribute('scoring-style') || 'radio';
  }

  get scoreData() {
    // Get existing score for this solo
    const heat = this.heatData;
    const judge = this.judgeData;
    const subject = heat.subjects[0];

    if (!subject || !subject.scores) return null;

    return subject.scores.find(s => s.judge_id === judge.id);
  }

  /**
   * Build dancers list for display
   */
  getDancersDisplay() {
    const heat = this.heatData;
    const subject = heat.subjects[0];

    if (!subject) return '';

    let dancers = [];

    // Skip if lead is "Nobody" (id = 0)
    if (subject.lead.id !== 0) {
      // Determine order based on column_order or professional status
      const columnOrder = this.judgeData.column_order || 1;
      if (columnOrder === 1 || subject.follow.type === 'Professional') {
        dancers.push(subject.lead);
        dancers.push(subject.follow);
      } else {
        dancers.push(subject.follow);
        dancers.push(subject.lead);
      }
    }

    // Add formations that are on floor
    if (subject.solo && subject.solo.formations) {
      subject.solo.formations.forEach(formation => {
        if (formation.on_floor) {
          dancers.push({ display_name: formation.person_name });
        }
      });
    }

    // Format dancers list
    if (dancers.length === 0) {
      return '';
    } else if (dancers.length === 1) {
      return dancers[0].name || dancers[0].display_name;
    } else if (dancers.length === 2) {
      // For two dancers (lead/follow), use join format without "and"
      const first = dancers[0].name || dancers[0].display_name;
      const second = dancers[1].name || dancers[1].display_name;
      // Split names and join them: "Murray, Arthur" + "Murray, Kathryn" -> "Arthur & Kathryn Murray"
      const firstParts = first.split(', ').reverse();
      const secondParts = second.split(', ').reverse();
      // If same last name, combine as "First & Second Last"
      if (firstParts.length > 1 && secondParts.length > 1 && firstParts[firstParts.length - 1] === secondParts[secondParts.length - 1]) {
        return `${firstParts[0]} & ${secondParts[0]} ${firstParts[firstParts.length - 1]}`;
      } else {
        return `${first} and ${second}`;
      }
    } else {
      const names = dancers.map(d => d.name || d.display_name);
      names[names.length - 1] = `and ${names[names.length - 1]}`;
      return names.join(', ');
    }
  }

  /**
   * Get studio name
   */
  getStudioName() {
    const heat = this.heatData;
    const subject = heat.subjects[0];

    if (!subject) return '';

    // Determine first dancer based on column order
    const columnOrder = this.eventData.column_order || 1;
    let firstDancer;

    if (subject.lead.id !== 0) {
      if (columnOrder === 1 || subject.follow.type === 'Professional') {
        firstDancer = subject.lead;
      } else {
        firstDancer = subject.follow;
      }
    }

    // Check first dancer's studio
    if (firstDancer && firstDancer.studio) {
      return firstDancer.studio.name;
    }

    // Check instructor's studio
    if (subject.instructor && subject.instructor.studio) {
      return subject.instructor.studio.name;
    }

    return '';
  }

  /**
   * Handle score change
   */
  handleScoreChange(event) {
    const input = event.target;
    const name = input.getAttribute('name');
    const value = input.value;

    // Prepare score data
    const data = {
      heat: this.heatData.subjects[0].id,
      score: value
    };

    // For 4-part scoring, include the field name
    if (name && this.eventData.solo_scoring === '4') {
      data.name = name;
    }

    // Send to server
    this.postScore(data, input);
  }

  /**
   * Handle comments change
   */
  handleCommentsChange(event) {
    const textarea = event.target;

    // Add visual feedback
    textarea.classList.remove('bg-gray-50');
    textarea.classList.add('bg-yellow-200');

    // Debounce the save
    if (this.commentTimeout) clearTimeout(this.commentTimeout);

    this.commentTimeout = setTimeout(() => {
      const data = {
        heat: this.heatData.subjects[0].id,
        comments: textarea.value
      };

      this.postScore(data, textarea);
      this.commentTimeout = null;
    }, 2000); // 2 second debounce for comments
  }

  /**
   * Handle start heat button
   */
  startHeat() {
    const button = this.querySelector('[data-action="start-heat"]');
    if (!button) return;

    // Don't allow starting heat if offline
    if (!navigator.onLine) {
      console.debug('[HeatSolo] Cannot start heat - offline');
      return;
    }

    fetch(this.getAttribute('start-action') || '', {
      method: 'POST',
      headers: window.inject_region({
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Content-Type': 'application/json'
      }),
      credentials: 'same-origin',
      body: JSON.stringify({
        heat: this.heatData.number
      })
    }).then(() => {
      button.style.display = 'none';
    });
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
    // Comments textarea
    const commentsTextarea = this.querySelector('textarea[data-target="comments"]');
    if (commentsTextarea) {
      commentsTextarea.addEventListener('input', (e) => this.handleCommentsChange(e));
    }

    // Score inputs
    const scoreInputs = this.querySelectorAll('input[data-target="score"]');
    scoreInputs.forEach(input => {
      input.addEventListener('change', (e) => this.handleScoreChange(e));
    });

    // Start heat button
    const startButton = this.querySelector('[data-action="start-heat"]');
    if (startButton) {
      startButton.addEventListener('click', () => this.startHeat());
    }
  }

  render() {
    const heat = this.heatData;
    const event = this.eventData;
    const subject = heat.subjects[0];

    if (!subject) {
      this.innerHTML = '<div class="text-center text-red-500">No subject data</div>';
      return;
    }

    const dancers = this.getDancersDisplay();
    const studio = this.getStudioName();
    const levelName = subject.level?.name || '';

    const score = this.scoreData;
    const comments = score?.comments || '';

    let contentHtml = '';

    if (this.style === 'emcee') {
      // Emcee view - show song/artist
      const solo = subject.solo;
      const song = solo?.song || '';
      const artist = solo?.artist || '';

      contentHtml = `
        ${song ? `<div class="mb-4"><b>Song</b>: ${song}</div>` : ''}
        ${artist ? `<div class="mb-4"><b>Artist</b>: ${artist}</div>` : ''}
      `;

      // Add start heat button if not current
      if (event.current_heat !== heat.number) {
        const isOnline = navigator.onLine;
        const disabledAttr = isOnline ? '' : 'disabled';
        const buttonClass = isOnline ? 'btn-green' : 'btn-gray';
        contentHtml += `
          <div class="text-center mt-2">
            <button data-action="start-heat" class="${buttonClass} text-sm" ${disabledAttr}>
              Start Heat
            </button>
          </div>
        `;
      }
    } else {
      // Judge view - show comments and scoring
      let scoreHtml = '';

      if (event.solo_scoring === '1') {
        // Single score (0-100)
        const scoreValue = score?.value || '';
        scoreHtml = `
          <b>Score:</b>
          <input data-target="score" value="${scoreValue}" type="number" min="0" max="100"
            class="border-2 border-black invalid:border-red-600 w-40 h-24 text-6xl text-center"/>
        `;
      } else {
        // 4-part scoring
        let results = {};
        if (score?.value) {
          try {
            results = score.value.startsWith('{') ? JSON.parse(score.value) : {};
          } catch (e) {
            console.error('Failed to parse score value:', e);
          }
        }

        scoreHtml = `
          <div class="grid grid-cols-4 gap-2">
            <div>
              <div class="text-center">Technique</div>
              <input data-target="score" name="technique" value="${results.technique || ''}" type="number" min="0" max="25"
                class="border-2 border-black invalid:border-red-600 w-32 h-24 text-6xl text-center"/>
            </div>
            <div>
              <div class="text-center">Execution</div>
              <input data-target="score" name="execution" value="${results.execution || ''}" type="number" min="0" max="25"
                class="border-2 border-black invalid:border-red-600 w-32 h-24 text-6xl text-center"/>
            </div>
            <div>
              <div class="text-center">Presentation</div>
              <input data-target="score" name="poise" value="${results.poise || ''}" type="number" min="0" max="25"
                class="border-2 border-black invalid:border-red-600 w-32 h-24 text-6xl text-center"/>
            </div>
            <div>
              <div class="text-center">Showmanship</div>
              <input data-target="score" name="showmanship" value="${results.showmanship || ''}" type="number" min="0" max="25"
                class="border-2 border-black invalid:border-red-600 w-32 h-24 text-6xl text-center"/>
            </div>
          </div>
        `;
      }

      contentHtml = `
        <label><b>Comments:</b></label>
        <textarea data-target="comments" data-heat="${subject.id}"
          class="grow block shadow rounded-md border border-gray-200 outline-none px-3 py-2 mt-2 w-full"
        >${comments}</textarea>

        <div>
          <div class="float-right mt-4">
            ${scoreHtml}
          </div>
          <div class="clear-both"></div>
        </div>
      `;
    }

    this.innerHTML = `
      <div class="grow w-full flex flex-col text-xl">
        <div class="hidden text-red-600 text-4xl" data-target="error"></div>

        <div class="mb-4">
          <div class="float-right"><b>Studio</b>: ${studio}</div>
          <div><b>Level</b>: ${levelName}</div>
          <div class="clear-both"></div>
        </div>

        <div class="mb-4"><span><b>Names</b>:&nbsp;</span><span>${dancers}</span></div>

        ${contentHtml}
      </div>
    `;
  }
}

customElements.define('heat-solo', HeatSolo);
