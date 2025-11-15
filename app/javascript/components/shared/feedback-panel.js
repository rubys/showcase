/**
 * FeedbackPanel - Feedback button panel component
 *
 * Renders feedback buttons (good/bad/value) and handles interactions.
 * Communicates with server via HeatDataManager and dispatches events
 * for parent components to update their state.
 *
 * Usage:
 *   <feedback-panel
 *     judge-id="55"
 *     heat="100"
 *     slot="1"
 *     good="F P"
 *     bad=""
 *     value="3"
 *     overall-options='["1","2","3","4","5"]'
 *     good-options='[{"abbr":"F","full":"Footwork"},...]'
 *     bad-options='[...]'>
 *   </feedback-panel>
 */

import { heatDataManager } from 'helpers/heat_data_manager';

class FeedbackPanel extends HTMLElement {
  connectedCallback() {
    this.parseAttributes();
    this.render();
    this.setupEventListeners();
  }

  parseAttributes() {
    this.judgeId = parseInt(this.getAttribute('judge-id'));
    this.heat = parseInt(this.getAttribute('heat'));

    // Parse slot: handle empty string, null, or "null" string as null
    // Note: Use _slotNumber instead of slot since slot is a built-in HTMLElement property
    const slotAttr = this.getAttribute('slot');
    if (!slotAttr || slotAttr === '' || slotAttr === 'null') {
      this._slotNumber = null;
    } else {
      const parsed = parseInt(slotAttr);
      this._slotNumber = isNaN(parsed) ? null : parsed;
    }

    this.good = this.getAttribute('good') || '';
    this.bad = this.getAttribute('bad') || '';
    this.value = this.getAttribute('value') || '';

    try {
      this.overallOptions = JSON.parse(this.getAttribute('overall-options') || '[]');
      this.goodOptions = JSON.parse(this.getAttribute('good-options') || '[]');
      this.badOptions = JSON.parse(this.getAttribute('bad-options') || '[]');
    } catch (e) {
      console.error('[FeedbackPanel] Failed to parse options:', e);
      this.overallOptions = [];
      this.goodOptions = [];
      this.badOptions = [];
    }
  }

  render() {
    const goodFeedback = this.good.split(' ').filter(f => f);
    const badFeedback = this.bad.split(' ').filter(f => f);

    this.innerHTML = `
      <div class="grid value w-full" data-value="${this.value}" style="grid-template-columns: 100px repeat(${this.overallOptions.length}, 1fr)">
        <div class="bg-gray-200 inline-flex justify-center items-center">Overall</div>
        ${this.overallOptions.map(opt => `
          <button class="open-fb ${this.value === opt ? 'selected' : ''}">
            <abbr title="${opt}">${opt}</abbr>
            <span>${opt}</span>
          </button>
        `).join('')}
      </div>
      <div class="grid good" data-value="${this.good}" style="grid-template-columns: 100px repeat(${this.goodOptions.length}, 1fr)">
        <div class="bg-gray-200 inline-flex justify-center items-center">Good</div>
        ${this.goodOptions.map(opt => `
          <button class="open-fb ${goodFeedback.includes(opt.abbr) ? 'selected' : ''}">
            <abbr title="${opt.full}">${opt.abbr}</abbr>
            <span>${opt.full}</span>
          </button>
        `).join('')}
      </div>
      <div class="grid bad" data-value="${this.bad}" style="grid-template-columns: 100px repeat(${this.badOptions.length}, 1fr)">
        <div class="bg-gray-200 inline-flex justify-center items-center">Needs Work</div>
        ${this.badOptions.map(opt => `
          <button class="open-fb ${badFeedback.includes(opt.abbr) ? 'selected' : ''}">
            <abbr title="${opt.full}">${opt.abbr}</abbr>
            <span>${opt.full}</span>
          </button>
        `).join('')}
      </div>
    `;
  }

  setupEventListeners() {
    const buttons = this.querySelectorAll('.open-fb');

    for (const button of buttons) {
      button.addEventListener('click', async () => {
        await this.handleFeedbackClick(button);
      });
    }
  }

  async handleFeedbackClick(button) {
    const feedbackType = button.parentElement.classList.contains('good') ? 'good' :
      (button.parentElement.classList.contains('bad') ? 'bad' : 'value');
    const feedbackValue = button.querySelector('abbr')?.textContent;

    // Get current values from all sections
    const sections = this.querySelectorAll('.value, .good, .bad');
    const currentScore = {};
    for (const section of sections) {
      const sectionType = section.classList.contains('good') ? 'good' :
        (section.classList.contains('bad') ? 'bad' : 'value');
      currentScore[sectionType] = section.dataset.value || '';
    }

    // Compute the new value locally for optimistic updates (used when offline)
    let computedValue;
    let computedOppositeValue;
    if (feedbackType === 'value') {
      // Overall score: radio button behavior (single selection)
      computedValue = feedbackValue;
    } else {
      // Good/Bad feedback: toggle behavior (multiple selections)
      const currentList = (currentScore[feedbackType] || '').split(' ').filter(f => f);
      const oppositeType = feedbackType === 'good' ? 'bad' : 'good';
      const oppositeList = (currentScore[oppositeType] || '').split(' ').filter(f => f);

      // Toggle the clicked feedback in the current list
      if (currentList.includes(feedbackValue)) {
        // Remove it (toggle off)
        computedValue = currentList.filter(f => f !== feedbackValue).join(' ');
        computedOppositeValue = currentScore[oppositeType]; // Unchanged
      } else {
        // Add it (toggle on) and remove from opposite list (mutual exclusivity)
        currentList.push(feedbackValue);
        computedValue = currentList.join(' ');

        // Update opposite list to remove this feedback (mutual exclusivity)
        const newOppositeList = oppositeList.filter(f => f !== feedbackValue);
        computedOppositeValue = newOppositeList.join(' ');
      }
    }

    // Send clicked value to server (server's post_feedback endpoint handles toggle logic)
    const scoreData = {
      heat: this.heat,
      slot: this._slotNumber,
      [feedbackType]: feedbackValue
    };

    // For offline saves: provide computed toggle values via special _computed fields
    // ScoreMergeHelper will use these for batch upload instead of the clicked value
    const enhancedCurrentScore = { ...currentScore };
    if (feedbackType !== 'value') {
      // Provide computed toggle values for offline merge
      // These ensure batch_scores endpoint gets correct toggled values
      enhancedCurrentScore._computedGood = feedbackType === 'good' ? computedValue : computedOppositeValue;
      enhancedCurrentScore._computedBad = feedbackType === 'bad' ? computedValue : computedOppositeValue;
    }

    try {
      const response = await heatDataManager.saveScore(this.judgeId, scoreData, enhancedCurrentScore);

      if (response && !response.error) {
        // Merge computed toggle values for offline behavior
        // When online: server returns properly toggled values, use those
        // When offline: server echoes back what we sent, use our computed toggle values
        const mergedResponse = { ...response };

        // For good/bad feedback: if server just echoed back what we sent (offline),
        // use our computed toggle values to ensure proper toggle behavior with mutual exclusivity
        if (feedbackType !== 'value' && response[feedbackType] === feedbackValue) {
          mergedResponse[feedbackType] = computedValue;
          const oppositeType = feedbackType === 'good' ? 'bad' : 'good';
          mergedResponse[oppositeType] = computedOppositeValue;
        }

        this.updateUI(mergedResponse);

        // Dispatch event for parent component to update in-memory data
        this.dispatchEvent(new CustomEvent('score-updated', {
          bubbles: true,
          detail: {
            heat: scoreData.heat,
            slot: this._slotNumber,
            ...mergedResponse  // Spread merged response to include computed toggle values
          }
        }));
      }
    } catch (error) {
      console.error('[FeedbackPanel] Failed to save feedback:', error);
    }
  }

  updateUI(response) {
    const sections = this.querySelectorAll('.value, .good, .bad');

    for (const section of sections) {
      const sectionType = section.classList.contains('good') ? 'good' :
        (section.classList.contains('bad') ? 'bad' : 'value');

      // Only update this section if it's in the response
      if (response[sectionType] === undefined) {
        continue;  // Skip sections not in response - preserves existing UI state
      }

      const feedbackValue = response[sectionType] || '';  // Handle null
      const feedback = feedbackValue.split(' ').filter(f => f);

      section.dataset.value = feedbackValue;

      for (const btn of section.querySelectorAll('button')) {
        const btnAbbr = btn.querySelector('abbr');
        if (btnAbbr && feedback.includes(btnAbbr.textContent)) {
          btn.classList.add('selected');
        } else {
          btn.classList.remove('selected');
        }
      }
    }
  }
}

customElements.define('feedback-panel', FeedbackPanel);

export default FeedbackPanel;
