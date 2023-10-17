import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="form-builder"
export default class extends Controller {
  connect() {
    this.columns = document.getElementById("columns");
    this.dances = document.getElementById("dances");
    this.columns.addEventListener("change", _event => {
      this.reflow();
      this.dances.style.gridTemplateColumns = `repeat(${this.columns.value}, 1fr)`;
    });

    for (let child of this.dances.children) {
      if (child.draggable) {
        child.addEventListener("dragstart", event => {
          event.dataTransfer.setData("application/drag-id", child.dataset.id);
          event.dataTransfer.effectAllowed = "move";
          child.style.opacity = 0.4;
        });

        child.addEventListener("dragend", _event => {
          child.style.opacity = 1;
          child.style.cursor = "default";
        });

        child.addEventListener("dragover", event => {
          event.dataTransfer.dropEffect = "move";
          event.preventDefault();
          return true;
        });

        child.addEventListener("drop", this.drop);
      }
    }

    this.reflow();

    document.getElementById("save").addEventListener("click", this.save);
  }

  reflow() {
    let columns = parseInt(this.columns.value);

    for (let div of [...this.dances.children]) {
      if (!div.draggable) div.remove();
    }

    let rows = Math.floor((this.dances.childElementCount + columns - 1) / columns);
    for (let child of this.dances.children) {
      if (child.style.gridRow && child.style.gridRow > rows) {
        rows = parseInt(child.style.gridRow);
      }
    }

    rows+=2;

    for (let i=this.dances.childElementCount; i < columns * rows; i++) {
      let div = document.createElement("div");
      div.textContent = "\xA0";
      div.addEventListener("drop", this.drop);

      div.addEventListener("dragover", event => {
        event.dataTransfer.dropEffect = "move";
        event.preventDefault();
        return true;
      });

      this.dances.appendChild(div);
    } 

    let dances = [...this.dances.children];

    for (let dance of dances) {
      if (dance.style.gridRow != "" && dance.style.gridColumn != "") {
        if (parseInt(dance.style.gridColumn) <= columns) continue;
      }

      let found = false;
      for (let row=1; !found; row++) {
        for (let col=1; col <= columns; col++) {
          if (!dances.some(div => (div != dance && parseInt(div.style.gridRow || 0) == row && parseInt(div.style.gridColumn || 0) == col))) {
            dance.style.gridRow = row;
            dance.style.gridColumn = col;
            found = true;
            break;
          }
        }
      }
    }
  }

  drop = event => {
    let source = event.dataTransfer.getData("application/drag-id");
    source = this.dances.querySelector(`div[data-id="${source}"]`);
    let target = event.target;

    [source.style.gridRow, target.style.gridRow] =
      [target.style.gridRow, source.style.gridRow];
    [source.style.gridColumn, target.style.gridColumn] =
      [target.style.gridColumn, source.style.gridColumn];

    document.getElementById("notice").textContent = "";

    this.reflow();

    event.preventDefault();
  };

  save = () => {
    const token = document.querySelector('meta[name="csrf-token"]').content;

    let positions = {};
    for (let dance of this.dances.children) {
      let id = dance.dataset.id;
      if (!id) continue;
      positions[id] = {row: dance.style.gridRow, col: dance.style.gridColumn};
    }

    fetch(this.element.action, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token,
        "Content-Type": "application/json"
      },
      credentials: "same-origin",
      redirect: "follow",
      body: JSON.stringify({dance: positions})
    }).then (response => response.text())
      .then(text => {document.getElementById("notice").textContent = text;});

    event.preventDefault();
  };
}
