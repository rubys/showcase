import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="heat-order"
export default class extends Controller {
  connect() {
    let heats = this.element.querySelectorAll(".heat-humber");
    for (let heat of heats) {
      heat.addEventListener("click", () => {
        let input = document.createElement("input");
        input.value = heat.textContent;
        input.style.textAlign = "center";
        heat.after(input);
        heat.style.display = "none";

        input.addEventListener("focus", () => {
          input.style.width = "3em";
        });

        input.addEventListener("blur", () => {
          input.style.width = input.value.length + "ch";
        });

        input.focus();
        const token = document.querySelector('meta[name="csrf-token"]').content;

        input.addEventListener("change", () => {
          fetch(this.element.getAttribute("data-renumber-action"), {
            method: "POST",
            headers: {
              "X-CSRF-Token": token,
              "Content-Type": "application/json"
            },
            credentials: "same-origin",
            redirect: "follow",
            body: JSON.stringify({ before: heat.textContent, after: input.value })
          }).then (response => response.text())
            .then(html => Turbo.renderStreamMessage(html));
        });
      });
    }
  }
}
