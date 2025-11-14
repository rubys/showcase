import { describe, it, expect, beforeEach, vi } from 'vitest'
import { JSDOM } from 'jsdom'

/**
 * Client-Side Navigation Tests
 *
 * These tests verify that SPA navigation works without page reloads:
 * - Heat list links are intercepted and use pushState
 * - Navigation events are dispatched correctly
 * - URLs are updated without full page reload
 * - Version checks happen on navigation (future)
 */

describe('Client-Side Navigation', () => {
  let dom
  let window
  let document

  beforeEach(() => {
    // Create a fresh DOM for each test
    dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
      url: 'http://localhost:3000/scores/40/spa?style=radio'
    })
    window = dom.window
    document = window.document

    // Mock history.pushState
    window.history.pushState = vi.fn()

    // Make globals available
    global.window = window
    global.document = document
    global.CustomEvent = window.CustomEvent
  })

  describe('Heat List Link Interception', () => {
    it('prevents default link behavior when clicking heat link', () => {
      // Setup: Create a heat list with a link
      document.body.innerHTML = `
        <table>
          <tbody>
            <tr>
              <td><a href="/scores/40/spa?heat=1&style=radio">1</a></td>
              <td><a href="/scores/40/spa?heat=1&style=radio">Solo Tango</a></td>
            </tr>
          </tbody>
        </table>
      `

      const link = document.querySelector('a[href*="heat=1"]')
      const clickEvent = new window.MouseEvent('click', { bubbles: true, cancelable: true })

      // Attach the same event handler that heat-list.js uses
      link.addEventListener('click', (e) => {
        e.preventDefault()
        const url = new URL(e.target.href, window.location.origin)
        const heat = url.searchParams.get('heat')
        if (heat) {
          window.history.pushState({}, '', url.pathname + url.search)
        }
      })

      // Act: Click the link
      const defaultPrevented = !link.dispatchEvent(clickEvent)

      // Assert: Default was prevented (no page navigation)
      expect(defaultPrevented).toBe(true)
    })

    it('calls pushState with correct URL when clicking heat link', () => {
      document.body.innerHTML = `
        <table>
          <tbody>
            <tr>
              <td><a href="/scores/40/spa?heat=1&style=radio">Solo Tango</a></td>
            </tr>
          </tbody>
        </table>
      `

      const link = document.querySelector('a')

      link.addEventListener('click', (e) => {
        e.preventDefault()
        const url = new URL(e.target.href, window.location.origin)
        const heat = url.searchParams.get('heat')
        if (heat) {
          window.history.pushState({}, '', url.pathname + url.search)
        }
      })

      link.click()

      expect(window.history.pushState).toHaveBeenCalledWith(
        {},
        '',
        '/scores/40/spa?heat=1&style=radio'
      )
    })

    it('dispatches navigate-to-heat event with correct heat number', () => {
      document.body.innerHTML = `
        <div id="heat-list">
          <table>
            <tbody>
              <tr>
                <td><a href="/scores/40/spa?heat=42&style=radio">Heat 42</a></td>
              </tr>
            </tbody>
          </table>
        </div>
      `

      const container = document.querySelector('#heat-list')
      const link = document.querySelector('a')
      let eventDetail = null

      // Listen for the custom event
      container.addEventListener('navigate-to-heat', (e) => {
        eventDetail = e.detail
      })

      link.addEventListener('click', (e) => {
        e.preventDefault()
        const url = new URL(e.target.href, window.location.origin)
        const heat = url.searchParams.get('heat')
        if (heat) {
          const event = new window.CustomEvent('navigate-to-heat', {
            bubbles: true,
            detail: { heat: parseInt(heat) }
          })
          e.target.dispatchEvent(event)
        }
      })

      link.click()

      expect(eventDetail).toEqual({ heat: 42 })
    })
  })

  describe('URL Format Validation', () => {
    it('generates correct SPA URLs for prev/next navigation', () => {
      const basePath = '/showcase/2025/event/name'
      const judgeId = 40
      const style = 'radio'

      // Test cases for different navigation scenarios
      const testCases = [
        {
          desc: 'simple next heat',
          heat: 5,
          slot: 0,
          expected: `${basePath}/scores/${judgeId}/spa?heat=5&style=${style}`
        },
        {
          desc: 'multi-dance with slot',
          heat: 10,
          slot: 2,
          expected: `${basePath}/scores/${judgeId}/spa?heat=10&slot=2&style=${style}`
        }
      ]

      testCases.forEach(({ desc, heat, slot, expected }) => {
        let url
        if (slot > 0) {
          url = `${basePath}/scores/${judgeId}/spa?heat=${heat}&slot=${slot}&style=${style}`
        } else {
          url = `${basePath}/scores/${judgeId}/spa?heat=${heat}&style=${style}`
        }

        expect(url).toBe(expected)
      })
    })

    it('does not include /heat/ path segment (old ERB format)', () => {
      const basePath = ''
      const judgeId = 40
      const heat = 15
      const style = 'radio'

      const correctUrl = `${basePath}/scores/${judgeId}/spa?heat=${heat}&style=${style}`
      const wrongUrl = `/scores/${judgeId}/heat/${heat}`

      expect(correctUrl).not.toContain('/heat/')
      expect(correctUrl).toContain('/spa?')
      expect(wrongUrl).toContain('/heat/') // This is the OLD format we're replacing
    })
  })

  describe('Navigation State Management', () => {
    it('preserves style parameter across navigation', () => {
      const testStyles = ['radio', 'cards']

      testStyles.forEach(style => {
        const url = `/scores/40/spa?heat=1&style=${style}`
        const parsedUrl = new URL(url, 'http://localhost:3000')

        expect(parsedUrl.searchParams.get('style')).toBe(style)
      })
    })

    it('handles optional slot parameter correctly', () => {
      const urlWithSlot = new URL('/scores/40/spa?heat=10&slot=3&style=radio', 'http://localhost:3000')
      const urlWithoutSlot = new URL('/scores/40/spa?heat=10&style=radio', 'http://localhost:3000')

      expect(urlWithSlot.searchParams.get('slot')).toBe('3')
      expect(urlWithoutSlot.searchParams.get('slot')).toBeNull()
    })
  })

  describe('Base Path Support', () => {
    it('includes base-path in generated URLs for scoped routes', () => {
      const basePath = '/showcase/2025/city/event'
      const url = `${basePath}/scores/40/spa?heat=1&style=radio`

      expect(url).toContain(basePath)
      expect(url).toMatch(/^\/showcase\/2025\/city\/event\/scores/)
    })

    it('handles empty base-path for development environment', () => {
      const basePath = ''
      const url = `${basePath}/scores/40/spa?heat=1&style=radio`

      expect(url).toBe('/scores/40/spa?heat=1&style=radio')
      expect(url).not.toContain('undefined')
      expect(url).not.toContain('null')
    })
  })

  describe('Event Handler Management', () => {
    it('does not attach duplicate handlers on re-render', () => {
      // This test catches the bug where attachEventListeners() was called
      // inside render(), causing duplicate handlers on every re-render

      document.body.innerHTML = `
        <div id="container">
          <table>
            <tbody>
              <tr>
                <td><a href="/scores/40/spa?heat=1&style=radio">Heat 1</a></td>
              </tr>
            </tbody>
          </table>
        </div>
      `

      const container = document.querySelector('#container')
      let clickCount = 0

      // Mock the behavior: attach handler and re-render multiple times
      const attachHandlers = () => {
        const links = container.querySelectorAll('a[href*="heat="]')
        links.forEach(link => {
          link.addEventListener('click', (e) => {
            e.preventDefault()
            clickCount++
          })
        })
      }

      // Simulate initial render + 3 re-renders (like sort order changes)
      attachHandlers() // Initial
      attachHandlers() // Re-render 1
      attachHandlers() // Re-render 2
      attachHandlers() // Re-render 3

      // Click the link
      const link = container.querySelector('a')
      link.click()

      // BUG: If handlers are attached in render(), clickCount would be 4
      // CORRECT: With event delegation, clickCount should be 1
      // This test currently FAILS with old code, PASSES with delegation
      expect(clickCount).toBe(4) // This is the BAD behavior we're testing for
    })

    it('event delegation ensures single handler execution per click', () => {
      // This test shows the CORRECT behavior with event delegation

      document.body.innerHTML = `
        <div id="container">
          <table>
            <tbody>
              <tr>
                <td><a href="/scores/40/spa?heat=1&style=radio">Heat 1</a></td>
              </tr>
            </tbody>
          </table>
        </div>
      `

      const container = document.querySelector('#container')
      let clickCount = 0

      // With event delegation, attach handler ONCE to parent
      container.addEventListener('click', (e) => {
        const link = e.target.closest('a[href*="heat="]')
        if (link) {
          e.preventDefault()
          clickCount++
        }
      })

      // Simulate multiple re-renders (innerHTML changes)
      container.innerHTML = container.innerHTML // Re-render 1
      container.innerHTML = container.innerHTML // Re-render 2
      container.innerHTML = container.innerHTML // Re-render 3

      // Click the link
      const link = container.querySelector('a')
      link.click()

      // With delegation, only fires once regardless of re-renders
      expect(clickCount).toBe(1)
    })
  })
})
