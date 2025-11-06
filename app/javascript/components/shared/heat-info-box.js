/**
 * HeatInfoBox - Displays contextual help and instructions
 *
 * Shows an info button that expands to display:
 * - Scoring instructions (based on heat type and style)
 * - Navigation instructions
 * - General tips
 */

export class HeatInfoBox extends HTMLElement {
  connectedCallback() {
    this.render();
    this.attachEventListeners();
  }

  get heatData() {
    return JSON.parse(this.getAttribute('heat-data') || '{}');
  }

  get eventData() {
    return JSON.parse(this.getAttribute('event-data') || '{}');
  }

  get style() {
    return this.getAttribute('style') || 'radio';
  }

  /**
   * Get scoring instruction text based on heat category and style
   */
  scoringInstructionText() {
    const { category } = this.heatData;
    const { open_scoring } = this.eventData;

    if (category === 'Solo') {
      return "Tab to or click on comments or score to edit. Press escape or click elsewhere to save.";
    } else if (this.style !== 'radio') {
      return this.scoringDragDropInstructions();
    } else if (open_scoring === '#') {
      return "Enter scores in the right most column. Tab to move to the next entry.";
    } else if (open_scoring === '+') {
      return this.scoringFeedbackInstructions();
    } else {
      return 'Click on the <em>radio</em> buttons on the right to score a couple. The last column, with a dash (<code>-</code>), means the couple hasn\'t been scored / didn\'t participate.';
    }
  }

  /**
   * Drag and drop scoring instructions
   */
  scoringDragDropInstructions() {
    return `Scoring can be done multiple ways:
      <ul class="list-disc ml-4">
        <li>Drag and drop: Drag an entry box to the desired score.</li>
        <li>Point and click: Clicking on a entry back and then clicking on score. Clicking on the back number again unselects it.</li>
        <li>Keyboard: tab to the desired entry back, then move it up and down using the keyboard. Clicking on escape unselects the back.</li>
      </ul>`;
  }

  /**
   * Feedback scoring instructions
   */
  scoringFeedbackInstructions() {
    return `Buttons on the left are used to indicated areas where the couple did well and will show up as <span class="good mx-0"><span class="open-fb selected px-2 mx-0">green</span></span> when selected.
      <li>Buttons on the right are used to indicate areas where the couple need improvement and will show up as <span class="bad mx-0"><span class="open-fb selected px-2 mx-0">red</span></span> when selected.`;
  }

  /**
   * Get navigation instruction text
   */
  navigationInstructionText() {
    const { category } = this.heatData;
    const { open_scoring } = this.eventData;

    const baseText = "Clicking on the arrows at the bottom corners will advance you to the next or previous heats. Left and right arrows on the keyboard may also be used";

    let suffix = "";
    if (category === 'Solo') {
      suffix = " when not editing comments or score";
    } else if (open_scoring === '#') {
      suffix = " when not entering scores";
    }

    return `${baseText}${suffix}. Swiping left and right on mobile devices and tablets also work.`;
  }

  /**
   * Toggle info box visibility
   */
  toggleInfoBox() {
    const infoBox = this.querySelector('.info-box');
    if (infoBox) {
      infoBox.classList.toggle('hidden');
    }
  }

  /**
   * Attach event listeners
   */
  attachEventListeners() {
    const button = this.querySelector('.info-button');
    if (button) {
      button.addEventListener('click', () => this.toggleInfoBox());
    }
  }

  render() {
    const { category } = this.heatData;
    const scoringInstructions = this.scoringInstructionText();
    const navigationInstructions = this.navigationInstructionText();

    // Build drag-drop instruction if applicable
    let dragDropInstruction = '';
    if (category !== 'Solo' && this.style !== 'emcee' && this.style !== 'radio') {
      dragDropInstruction = '<li>Dragging an entry back to the unlabelled box at the right returns the participant to the unscored state.</li>';
    }

    this.innerHTML = `
      <div>
        <div class="info-button top-2">&#x24D8;</div>
        <ul class="info-box hidden">
          <li>${scoringInstructions}</li>
          ${dragDropInstruction}
          <li>${navigationInstructions}</li>
          <li>Clicking on the heat information at the top center of the page will return you to the heat list where you can quickly scroll and select a different heat.</li>
        </ul>
      </div>
    `;
  }
}

customElements.define('heat-info-box', HeatInfoBox);
