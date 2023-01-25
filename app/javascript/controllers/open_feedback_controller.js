import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="open-feedback"
export default class extends Controller {
  connect() {
    let previous = this.element.previousElementSibling;

    this.element.addEventListener('mouseenter', () => {
      previous.classList.add('bg-yellow-200');
    });

    this.element.addEventListener('mouseleave', () => {
      previous.classList.remove('bg-yellow-200');
    });

    for (let button of this.element.querySelectorAll('button')) {
      let span = button.querySelector('span');
      let abbr = button.querySelector('abbr');
      if (span && abbr) {
        abbr.title = span.textContent;
        if (abbr.textContent == button.parentElement.dataset.value) {
          button.classList.add('selected');
        }
      }

      button.addEventListener('click', event => {


        const token = document.querySelector('meta[name="csrf-token"]').content;
        const score = document.querySelector('div[data-controller=score]');

        let feedbackType = button.parentElement.classList.contains('good') ? 'good' : 'bad';
        let feedbackValue = button.querySelector('abbr').textContent;
        if (button.classList.contains("selected")) feedbackValue = null;

        const feedback = {
          heat: parseInt(this.element.dataset.heat),
          slot: score.dataset.slot && parseInt(score.dataset.slot),
          [feedbackType] : feedbackValue
        }

        fetch(this.element.dataset.feedbackAction, {
          method: 'POST',
          headers: {
            'X-CSRF-Token': token,
            'Content-Type': 'application/json'
          },
          credentials: 'same-origin',
          redirect: 'follow',
          body: JSON.stringify(feedback)
        }).then(response => {
          let error = document.querySelector('div[data-score-target=error]');
    
          if (response.ok) {
            error.style.display = 'none';

            for (let unselect of button.parentElement.querySelectorAll('button')) {
              if (unselect != button) unselect.classList.remove('selected');
            }

            if (feedbackValue == null) {
              button.classList.remove('selected');
            } else {
              button.classList.add('selected');
            }
          } else {
            error.textContent = response.statusText;
            error.style.display = 'block';
          }
    
          return response;
        })
      })
    }
  }
}
