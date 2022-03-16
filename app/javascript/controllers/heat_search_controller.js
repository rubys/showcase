import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="heat-search"
export default class extends Controller {
  static targets = ["input", "nav"];

  keydown = event => {
    if (event.key == 'ArrowRight') {
      let link = document.querySelector('div[rel=next]');
      if (link) link.click();
    } else if (event.key == 'ArrowLeft') {
      let link = document.querySelector('div[rel=prev]');
      if (link) link.click();
    }
  }

  disconnect() {
    document.body.removeEventListener('keydown', this.keydown);
  }

  connect() {
    document.body.addEventListener('keydown', this.keydown);

    let input = this.inputTarget;
    let search = this.search.bind(this);

    this.page = 1;

    this.heats = [];
    let rows = null;
    for (let tr of this.element.querySelectorAll('tr')) {
      if (tr.parentElement.nodeName == 'THEAD') {
        rows = [];
        let head = tr.parentElement;
        let number = head.querySelector('span').textContent;
        this.heats.push({ number, head, rows });
      } else {
        let text = tr.querySelector('td[data-index]').textContent.toLowerCase();
        rows.push([text, tr]);
      }
    }

    this.search(input.value);
    this.seek();

    const observer = new MutationObserver(this.seek);
    const config = { attributes: true, childList: true, subtree: true };
    let currentHeat = document.getElementById('current-heat');
    observer.observe(currentHeat.parentElement, config);

    input.addEventListener('input', event => {
      this.search(input.value)
    });

    this.element.querySelector('div[rel=prev').addEventListener('click', () => {
      if (this.page > 1) this.setPage(this.page - 1);
    });

    this.element.querySelector('div[rel=next').addEventListener('click', () => {
      if (this.page < this.totalPages) this.setPage(this.page + 1);
    });
  }

  setPage(page) {
    this.page = page;
    this.navigate();
  }

  seek = () => {
    let currentHeat = document.getElementById('current-heat').textContent.trim();

    let heat = this.heats.find(heat => heat.number == currentHeat);

    if (heat && heat.show?.length == 0) {
      currentHeat = parseInt(currentHeat);
      heat = this.heats.find(heat => (
        parseInt(heat.number) > currentHeat && heat.show?.length
      ))
    }

    if (heat?.page && heat.page != this.page) this.setPage(heat.page);

    if (heat && heat.head.style.display != 'none') {
      heat.head.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  search = (value) => {
    value = value.toLowerCase();

    let counter = 0;
    let pages = 1;

    for (let heat of this.heats) {
      heat.show = [];

      for (let [text, tr] of heat.rows) {
        if (text.includes(value)) {
          heat.show.push(tr);
        }
      }

      if (counter + heat.show.length > 100) {
        pages++;
        counter = 0;
      }

      heat.page = pages;
      counter += heat.show.length;
    };

    if (this.page > pages) {
      this.page = pages;
    };

    this.totalPages = pages;
    this.navigate();
  }

  navigate() {
    let pages = this.totalPages;

    for (let { head, rows, show, page } of this.heats) {
      if (page != this.page) {
        show = [];
      }

      if (show.length > 0) {
        head.style.display = 'table-header-group';
      } else {
        head.style.display = 'none';
      }

      for (let [_text, tr] of rows) {
        if (show.includes(tr)) {
          tr.style.display = 'table-row';
        } else {
          tr.style.display = 'none';
        }
      }
    }

    let navTarget = this.navTarget;
    let prev = navTarget.firstElementChild;
    let next = navTarget.lastElementChild;
    for (let child of [...navTarget.children]) {
      if (child != prev && child != next) child.remove();
    }

    const addPage = (page) => {
      let div = document.createElement('div');
      div.classList.add('border', 'py-2', 'px-2');
      div.textContent = page;
      let li = document.createElement('li');
      li.classList.add('mx-4');
      if (page == this.page) {
        div.classList.add('bg-black', 'text-orange-300');
      } else if (typeof page == 'number') {
        li.addEventListener('click', () => { this.setPage(page) })
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
