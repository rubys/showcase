import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="heat-search"
export default class extends Controller {
  static targets = [ "input", "nav" ]

  connect() {
    let input = this.inputTarget;
    let search = this.search.bind(this);

    this.page = 1;

    this.rows = [];
    for (let tbody of this.element.querySelectorAll('tbody')) {
      let text = tbody.querySelector('td[data-index]').textContent.toLowerCase();
      this.rows.push([text, tbody]);
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

    let start = (this.page - 1) * 100;
    let finish = start + 99;
    let counter = 0;

    for (let [text, tbody] of this.rows) {
      if (text.includes(value)) {
        if (counter >= start && counter <= finish) {
          tbody.style.display = 'table-row-group';
        } else {
          tbody.style.display = 'none';
        }
        counter++;
      } else {
        tbody.style.display = 'none';
      }
    }

    let pages = Math.ceil(counter / 100);
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
        li.addEventListener('click', () => {setPage(page)})
      }
      li.appendChild(div);
      navTarget.insertBefore(li, next);
    }

    if (this.page < 5) {
      if (pages < 7) {
        for (let page=1; page <= pages; page++) addPage(page);
      } else {
        for (let page=1; page <= 5; page++) addPage(page);
        addPage('...');
        addPage(pages);
      }
    } else {
      addPage(1);
      addPage('...');
      if (this.page + 3 >= pages) {
        console.log(this.page, this.page + 3, pages, this.page+3 <= pages);
        for (let page=this.page-1; page <= pages; page++) addPage(page);
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
