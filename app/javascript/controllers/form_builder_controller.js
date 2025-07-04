import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="form-builder"
export default class extends Controller {
  static values = { 
    modelName: String,
    saveUrl: String
  }

  connect() {
    this.columns = document.getElementById("columns");
    this.grid = document.getElementById("grid");
    this.columns.addEventListener("change", _event => {
      this.reflow();
      this.grid.style.gridTemplateColumns = `repeat(${this.columns.value}, 1fr)`;
    });

    for (let child of this.grid.children) {
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
    
    // Add save-and-renumber functionality
    const saveAndRenumberBtn = document.getElementById("save-and-renumber");
    if (saveAndRenumberBtn) {
      saveAndRenumberBtn.addEventListener("click", this.saveAndRenumber);
    }
  }

  reflow() {
    let columns = parseInt(this.columns.value);

    for (let div of [...this.grid.children]) {
      if (!div.draggable) div.remove();
    }

    let rows = Math.floor((this.grid.childElementCount + columns - 1) / columns);
    for (let child of this.grid.children) {
      if (child.style.gridRow && child.style.gridRow > rows) {
        rows = parseInt(child.style.gridRow);
      }
    }

    rows+=2;

    for (let i=this.grid.childElementCount; i < columns * rows; i++) {
      let div = document.createElement("div");
      div.textContent = "\xA0";
      div.addEventListener("drop", this.drop);

      div.addEventListener("dragover", event => {
        event.dataTransfer.dropEffect = "move";
        event.preventDefault();
        return true;
      });

      this.grid.appendChild(div);
    } 

    let items = [...this.grid.children];

    for (let item of items) {
      if (item.style.gridRow != "" && item.style.gridColumn != "") {
        if (parseInt(item.style.gridColumn) <= columns) continue;
      }

      let found = false;
      for (let row=1; !found; row++) {
        for (let col=1; col <= columns; col++) {
          if (!items.some(div => (div != item && parseInt(div.style.gridRow || 0) == row && parseInt(div.style.gridColumn || 0) == col))) {
            item.style.gridRow = row;
            item.style.gridColumn = col;
            found = true;
            break;
          }
        }
      }
    }
  }

  drop = event => {
    let source = event.dataTransfer.getData("application/drag-id");
    source = this.grid.querySelector(`div[data-id="${source}"]`);
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
    for (let item of this.grid.children) {
      let id = item.dataset.id;
      if (!id) continue;
      positions[id] = {row: item.style.gridRow, col: item.style.gridColumn};
    }

    let data = {};
    data[this.modelNameValue] = positions;

    fetch(this.saveUrlValue, {
      method: "POST",
      headers: window.inject_region({
        "X-CSRF-Token": token,
        "Content-Type": "application/json"
      }),
      credentials: "same-origin",
      redirect: "follow",
      body: JSON.stringify(data)
    }).then (response => response.text())
      .then(text => {document.getElementById("notice").textContent = text;});

    event.preventDefault();
  };

  saveAndRenumber = (event) => {
    event.preventDefault();
    
    const token = document.querySelector('meta[name="csrf-token"]').content;
    const renumberUrl = event.target.dataset.renumberUrl;

    let positions = {};
    for (let item of this.grid.children) {
      let id = item.dataset.id;
      if (!id) continue;
      positions[id] = {row: item.style.gridRow, col: item.style.gridColumn};
    }

    let data = {};
    data[this.modelNameValue] = positions;

    // First save the positions
    fetch(this.saveUrlValue, {
      method: "POST",
      headers: window.inject_region({
        "X-CSRF-Token": token,
        "Content-Type": "application/json"
      }),
      credentials: "same-origin",
      redirect: "follow",
      body: JSON.stringify(data)
    }).then(response => {
      if (response.ok) {
        // Then submit the renumber form
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = renumberUrl;
        
        const methodInput = document.createElement('input');
        methodInput.type = 'hidden';
        methodInput.name = '_method';
        methodInput.value = 'patch';
        
        const tokenInput = document.createElement('input');
        tokenInput.type = 'hidden';
        tokenInput.name = 'authenticity_token';
        tokenInput.value = token;
        
        form.appendChild(methodInput);
        form.appendChild(tokenInput);
        document.body.appendChild(form);
        form.submit();
      }
    });
  };
}