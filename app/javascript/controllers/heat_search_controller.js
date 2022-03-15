import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="heat-search"
export default class extends Controller {
  static targets = ["input", "nav"]

  connect() {
    let input = this.inputTarget;
    let search = this.search.bind(this);

    this.page = 1;

    this.heats = [];
    let rows = null;
    for (let tr of this.element.querySelectorAll('tr')) {
      if (tr.parentElement.nodeName == 'THEAD') {
        rows = [];
        this.heats.push([tr.parentElement, rows]);
      } else {
        let text = tr.querySelector('td[data-index]').textContent.toLowerCase();
        rows.push([text, tr]);
      }
    }

    search(input.value);

    input.addEventListener('input', event => {
      search(input.value)
    })
  }

  setPage(page) {
    this.page = page;
    this.search(this.inputTarget.value);
  }

  search(value) {
    value = value.toLowerCase();

    let counter = 0;
    let pages = 1;

    for (let [thead, rows] of this.heats) {
      let show = [];

      for (let [text, tr] of rows) {
        if (text.includes(value)) {
          show.push(tr);
        }
      }

      if (counter + show.length > 100) {
        pages++;
        counter = 0;
      } else {
        counter += show.length;
      }

      if (pages != this.page) {
        show = [];
      }

      if (show.length > 0) {
        thead.style.display = 'table-header-group';
      } else {
        thead.style.display = 'none';
      }

      for (let [text, tr] of rows) {
        if (show.includes(tr)) {
          tr.style.display = 'table-row';
        } else {
          tr.style.display = 'none';
        }
      }
    }

    if (this.page > pages) {
      this.page = pages;
      return this.search(value);
    }

    let navTarget = this.navTarget;
    let prev = navTarget.firstElementChild;
    let next = navTarget.lastElementChild;
    for (let child of [...navTarget.children]) {
      if (child != prev && child != next) child.remove();
    }

    let currentPage = this.page;
    let setPage = this.setPage.bind(this);

    function addPage(page) {
      let div = document.createElement('div');
      div.classList.add('border', 'py-2', 'px-2');
      div.textContent = page;
      let li = document.createElement('li');
      li.classList.add('mx-4');
      if (page == currentPage) {
        div.classList.add('bg-black', 'text-orange-300');
      } else if (typeof page == 'number') {
        li.addEventListener('click', () => { setPage(page) })
      }
      li.appendChild(div);
      navTarget.insertBefore(li, next);
    }

    if (this.page < 5) {
      if (pages < 7) {
        for (let page = 1; page <= pages; page++) addPage(page);
      } else {
        for (let page = 1; page <= 5; page++) addPage(page);
        addPage('...');
        addPage(pages);
      }
    } else {
      addPage(1);
      addPage('...');
      if (this.page + 3 >= pages) {
        for (let page = this.page - 1; page <= pages; page++) addPage(page);
      } else {
        addPage(this.page - 1);
        addPage(this.page);
        addPage(this.page + 1);
        addPage('...');
        addPage(pages);
      }
    }
  }
}
