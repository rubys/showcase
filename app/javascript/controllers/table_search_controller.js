import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "nav"]
  
  connect() {
    this.input = this.inputTarget
    this.nav = this.navTarget
    this.tables = this.element.querySelectorAll('tbody')
    this.currentPage = 1
    this.itemsPerPage = 10
    
    // Set up event listeners
    this.input.addEventListener('input', () => this.filterTables())
    this.nav.addEventListener('click', (e) => this.handleNavClick(e))
    
    // Initial filter if search value exists
    if (this.input.value) {
      this.filterTables()
    }
  }
  
  filterTables() {
    const searchTerm = this.input.value.toLowerCase()
    let visibleTables = []
    
    this.tables.forEach(tbody => {
      // Find the thead that immediately precedes this tbody
      let thead = tbody.previousElementSibling
      while (thead && thead.nodeName !== 'THEAD') {
        thead = thead.previousElementSibling
      }
      
      const rows = tbody.querySelectorAll('tr')
      let visibleRows = []
      
      // Filter rows based on search term
      rows.forEach(row => {
        const text = row.textContent.toLowerCase()
        if (searchTerm === '' || text.includes(searchTerm)) {
          row.style.display = ''
          visibleRows.push(row)
        } else {
          row.style.display = 'none'
        }
      })
      
      // Show/hide header based on visible rows
      if (visibleRows.length > 0) {
        if (thead) {
          thead.style.display = 'table-header-group'
        }
        visibleTables.push(tbody)
      } else {
        if (thead) {
          thead.style.display = 'none'
        }
      }
    })
    
    this.currentPage = 1
    this.updatePagination(visibleTables)
  }
  
  handleNavClick(e) {
    const target = e.target
    if (!target.getAttribute('rel')) return
    
    const rel = target.getAttribute('rel')
    const visibleTables = this.getVisibleTables()
    const totalPages = Math.ceil(visibleTables.length / this.itemsPerPage)
    
    if (rel === 'prev' && this.currentPage > 1) {
      this.currentPage--
    } else if (rel === 'next' && this.currentPage < totalPages) {
      this.currentPage++
    }
    
    this.updatePagination(visibleTables)
  }
  
  getVisibleTables() {
    return Array.from(this.tables).filter(tbody => {
      const table = tbody.closest('table')
      return table.style.display !== 'none'
    })
  }
  
  updatePagination(visibleTables) {
    const totalPages = Math.ceil(visibleTables.length / this.itemsPerPage)
    const startIndex = (this.currentPage - 1) * this.itemsPerPage
    const endIndex = startIndex + this.itemsPerPage
    
    // Hide all tables first
    this.tables.forEach(tbody => {
      const table = tbody.closest('table')
      table.style.display = 'none'
    })
    
    // Show only tables for current page
    visibleTables.slice(startIndex, endIndex).forEach(tbody => {
      const table = tbody.closest('table')
      table.style.display = ''
    })
    
    // Update navigation
    const pageNumber = this.nav.querySelector('div:not([rel])')
    if (pageNumber) {
      pageNumber.textContent = this.currentPage
    }
    
    // Update nav button states
    const prevButton = this.nav.querySelector('[rel="prev"]')
    const nextButton = this.nav.querySelector('[rel="next"]')
    
    if (prevButton) {
      prevButton.classList.toggle('opacity-50', this.currentPage === 1)
      prevButton.style.cursor = this.currentPage === 1 ? 'not-allowed' : 'pointer'
    }
    
    if (nextButton) {
      nextButton.classList.toggle('opacity-50', this.currentPage === totalPages || totalPages === 0)
      nextButton.style.cursor = (this.currentPage === totalPages || totalPages === 0) ? 'not-allowed' : 'pointer'
    }
  }
}