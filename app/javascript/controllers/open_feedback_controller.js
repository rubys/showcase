import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="open-feedback"
export default class extends Controller {
  connect() {
    let previous = this.element.previousElementSibling;

    this.element.addEventListener("mouseenter", () => {
      previous.classList.add("bg-yellow-200");
    });

    this.element.addEventListener("mouseleave", () => {
      previous.classList.remove("bg-yellow-200");
    });

    let next = this.element.nextElementSibling;

    if (next && next.querySelector("textarea")) {
      next.addEventListener("mouseenter", () => {
        previous.classList.add("bg-yellow-200");
      });
  
      next.addEventListener("mouseleave", () => {
        previous.classList.remove("bg-yellow-200");
      });
    }

    for (let button of this.element.querySelectorAll("button")) {
      button.disabled = false;
      
      let span = button.querySelector("span");
      let abbr = button.querySelector("abbr");
      if (span && abbr) {
        abbr.title = span.textContent;
        let feedback = button.parentElement.dataset.value.split(" ");
        if (feedback.includes(abbr.textContent)) {
          button.classList.add("selected");
        }
      }

      button.addEventListener("click", _event => {
        const token = document.querySelector('meta[name="csrf-token"]').content;
        const score = document.querySelector("div[data-controller=score]");

        let feedbackType = button.parentElement.classList.contains("good") ? "good" : 
          (button.parentElement.classList.contains("bad") ? "bad" : "value");
        let feedbackValue = button.querySelector("abbr").textContent;

        const feedback = {
          heat: parseInt(this.element.dataset.heat),
          slot: score.dataset.slot && parseInt(score.dataset.slot),
          [feedbackType] : feedbackValue
        };

        fetch(this.element.dataset.feedbackAction, {
          method: "POST",
          headers: window.inject_region({
            "X-CSRF-Token": token,
            "Content-Type": "application/json"
          }),
          credentials: "same-origin",
          redirect: "follow",
          body: JSON.stringify(feedback)
        }).then(response => response.ok ? response.text() : JSON.stringify({error: response.statusText}))
          .then(response => {
            response = JSON.parse(response);
            let error = document.querySelector("div[data-score-target=error]");
    
            if (!response.error) {
              error.style.display = "none";

              let sections = button.parentElement.parentElement.children;
              for (let section of sections) {
                let feedbackType = section.classList.contains("good") ? "good" : 
                  (section.classList.contains("bad") ? "bad" : "value");
                let feedback = (response[feedbackType] || "").split(" ");
            
                for (let button of section.querySelectorAll("button")) {
                  if (feedback.includes(button.querySelector("abbr").textContent)) {
                    button.classList.add("selected");
                  } else {
                    button.classList.remove("selected");
                  }
                }
              }
            } else {
              error.textContent = response.error;
              error.style.display = "block";
            }
    
            return response;
          });
      });
    }
  }
}
