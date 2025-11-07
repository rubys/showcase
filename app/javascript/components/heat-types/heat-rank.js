/**
 * HeatRank - Ranking/finals heat with drag-and-drop ordering
 *
 * Renders a finals heat with:
 * - Draggable table rows for ranking
 * - Back number, names, category, studio
 * - Visual feedback during drag operations
 * - Auto-save ranking to server
 * - Start heat button (for emcee)
 */

export class HeatRank extends HTMLElement {
  connectedCallback() {
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

  get style() {
    return this.getAttribute('style') || 'radio';
  }

  get slot() {
    return parseInt(this.getAttribute('slot') || '0');
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
   * Handle drag start
   */
  handleDragStart(event, element) {
    this.draggedElement = element;
    element.style.opacity = '0.4';
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/html', element.innerHTML);
  }

  /**
   * Handle drag over
   */
  handleDragOver(event) {
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
    return true;
  }

  /**
   * Handle drag enter
   */
  handleDragEnter(element) {
    element.classList.add('bg-blue-100');
  }

  /**
   * Handle drag leave
   */
  handleDragLeave(element) {
    element.classList.remove('bg-blue-100');
  }

  /**
   * Handle drop
   */
  handleDrop(event, dropTarget) {
    event.stopPropagation();
    event.preventDefault();

    dropTarget.classList.remove('bg-blue-100');

    if (this.draggedElement && this.draggedElement !== dropTarget) {
      const tbody = dropTarget.parentElement;
      const rows = Array.from(tbody.querySelectorAll('tr[draggable="true"]'));

      const draggedIndex = rows.indexOf(this.draggedElement);
      const dropIndex = rows.indexOf(dropTarget);

      if (draggedIndex < dropIndex) {
        tbody.insertBefore(this.draggedElement, dropTarget.nextSibling);
      } else {
        tbody.insertBefore(this.draggedElement, dropTarget);
      }

      // Update ranks and save
      this.updateRanks();
      this.saveRanking();
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
   * Update rank numbers in the table
   */
  updateRanks() {
    const rows = this.querySelectorAll('tr[draggable="true"]');
    rows.forEach((row, index) => {
      const rankCell = row.querySelector('td:first-child');
      if (rankCell) {
        rankCell.textContent = index + 1;
      }
      row.setAttribute('data-rank', index + 1);
    });
  }

  /**
   * Save ranking to server
   */
  saveRanking() {
    const rows = this.querySelectorAll('tr[draggable="true"]');
    const ranking = Array.from(rows).map((row, index) => ({
      id: parseInt(row.getAttribute('data-drag-id')),
      rank: index + 1
    }));

    const data = {
      slot: this.slot,
      ranking: ranking
    };

    fetch(this.getAttribute('drop-action') || '', {
      method: 'POST',
      headers: window.inject_region({
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Content-Type': 'application/json'
      }),
      credentials: 'same-origin',
      body: JSON.stringify(data)
    }).then(response => {
      if (!response.ok) {
        const errorDiv = this.querySelector('[data-target="error"]');
        if (errorDiv) {
          errorDiv.textContent = 'Failed to save ranking';
          errorDiv.classList.remove('hidden');
        }
      }
    }).catch(error => {
      console.error('Failed to save ranking:', error);
    });
  }

  /**
   * Handle start heat button
   */
  startHeat() {
    const button = this.querySelector('[data-action="start-heat"]');
    if (!button) return;

    // Don't allow starting heat if offline
    if (!navigator.onLine) {
      console.log('[HeatRank] Cannot start heat - offline');
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
   * Attach event listeners
   */
  attachEventListeners() {
    const rows = this.querySelectorAll('tr[draggable="true"]');

    rows.forEach(row => {
      row.addEventListener('dragstart', (e) => this.handleDragStart(e, row));
      row.addEventListener('dragover', (e) => this.handleDragOver(e));
      row.addEventListener('dragenter', () => this.handleDragEnter(row));
      row.addEventListener('dragleave', () => this.handleDragLeave(row));
      row.addEventListener('drop', (e) => this.handleDrop(e, row));
      row.addEventListener('dragend', () => this.handleDragEnd(row));
    });

    // Start heat button
    const startButton = this.querySelector('[data-action="start-heat"]');
    if (startButton) {
      startButton.addEventListener('click', () => this.startHeat());
    }
  }

  render() {
    const heat = this.heatData;
    const subjects = heat.subjects;
    const judge = this.judgeData;
    const columnOrder = judge.column_order || 1;

    // Build table headers
    const leadHeader = columnOrder === 1 ? 'Lead' : 'Student';
    const followHeader = columnOrder === 1 ? 'Follow' : 'Instructor';

    // Build table rows
    const rowsHtml = subjects.length === 0
      ? '<tr><td colspan="6"><p class="m-5">No couples on the floor for this heat.</p></td></tr>'
      : subjects.map((subject, index) => {
          const entry = subject;
          const subcat = this.getSubjectCategory(entry);
          const isScratched = subject.number <= 0;

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
          if (this.combineOpenAndClosed && ['Open', 'Closed'].includes(heat.category)) {
            categoryDisplay = `${heat.category} - ${subcat}`;
          }

          const trClasses = isScratched
            ? 'hover:bg-yellow-200 line-through opacity-50'
            : 'hover:bg-yellow-200 cursor-move transition-colors duration-200';

          const draggable = isScratched ? 'false' : 'true';

          return `
            <tr class="${trClasses}"
                id="heat-${subject.id}"
                ${!isScratched ? `draggable="true" data-drag-id="${subject.id}" data-rank="${index + 1}"` : ''}>
              <td class="text-2xl font-bold px-2">${index + 1}</td>
              <td class="text-xl"><span>${subject.lead.back}</span></td>
              <td>${firstName}</td>
              <td>${secondName}</td>
              <td>${categoryDisplay}</td>
              <td>${subject.studio || ''}</td>
            </tr>
          `;
        }).join('');

    // Add start heat button if emcee and not current
    let startButtonHtml = '';
    if (this.style === 'emcee' && this.eventData.current_heat !== heat.number) {
      const isOnline = navigator.onLine;
      const disabledAttr = isOnline ? '' : 'disabled';
      const buttonClass = isOnline ? 'btn-green' : 'btn-gray';
      startButtonHtml = `
        <div class="text-center mt-2">
          <button data-action="start-heat" class="${buttonClass} text-sm" ${disabledAttr}>
            Start Heat
          </button>
        </div>
      `;
    }

    this.innerHTML = `
      <div id="rank-heat-container" class="grow flex flex-col border-2 border-slate-400 overflow-y-auto">
        <div class="grow flex flex-col border-2 border-slate-400 overflow-y-auto" id="slot-${this.slot}">
          <div class="hidden text-red-600 text-4xl" data-target="error"></div>

          <table class="table-auto border-separate border-spacing-y-1 mx-4">
            <thead>
              <tr>
                <th class="text-left border-b-2 border-black" rowspan="2">Rank</th>
                <th class="text-left border-b-2 border-black" rowspan="2">Back</th>
                <th class="text-left border-b-2 border-black" rowspan="2">${leadHeader}</th>
                <th class="text-left border-b-2 border-black" rowspan="2">${followHeader}</th>
                <th class="text-left border-b-2 border-black" rowspan="2">Category</th>
                <th class="text-left border-b-2 border-black" rowspan="2">Studio</th>
              </tr>
            </thead>
            <tbody>
              ${rowsHtml}
            </tbody>
          </table>

          ${startButtonHtml}
        </div>
      </div>
    `;
  }
}

customElements.define('heat-rank', HeatRank);
