import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { JSDOM } from 'jsdom'

/**
 * FeedbackPanel Tests
 *
 * Tests for the FeedbackPanel component that handles feedback button
 * rendering and interactions (good/bad/value scoring).
 */

describe('FeedbackPanel', () => {
  let dom
  let window
  let document
  let FeedbackPanel

  beforeEach(async () => {
    // Reset modules to ensure clean state
    vi.resetModules()

    // Create a fresh DOM for each test
    dom = new JSDOM('<!DOCTYPE html><html><body></body></html>')
    window = dom.window
    document = window.document

    // Mock globals
    global.window = window
    global.document = document
    global.CustomEvent = window.CustomEvent
    global.HTMLElement = window.HTMLElement
    global.customElements = window.customElements

    // Mock inject_region helper
    window.inject_region = (headers) => headers

    // Mock heatDataManager before importing FeedbackPanel
    const mockHeatDataManager = {
      saveScore: vi.fn(() => Promise.resolve({ good: 'F P' }))
    }

    vi.doMock('../../app/javascript/helpers/heat_data_manager.js', () => ({
      heatDataManager: mockHeatDataManager
    }))

    // Import FeedbackPanel after mocking - this will auto-register the custom element
    await import('../../app/javascript/components/shared/feedback-panel.js')
  })

  afterEach(() => {
    vi.clearAllMocks()
    document.body.innerHTML = ''
  })

  describe('Rendering', () => {
    it('renders overall value buttons', () => {
      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('value', '3')
      panel.setAttribute('overall-options', '["1","2","3","4","5"]')
      panel.setAttribute('good-options', '[]')
      panel.setAttribute('bad-options', '[]')

      document.body.appendChild(panel)

      const valueSection = panel.querySelector('.value')
      expect(valueSection).toBeTruthy()
      expect(valueSection.dataset.value).toBe('3')

      const buttons = valueSection.querySelectorAll('button')
      expect(buttons).toHaveLength(5)

      // Check that button 3 is selected
      const selectedButton = valueSection.querySelector('button.selected')
      expect(selectedButton).toBeTruthy()
      expect(selectedButton.querySelector('abbr').textContent).toBe('3')
    })

    it('renders good feedback buttons with selections', () => {
      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('good', 'F P')
      panel.setAttribute('overall-options', '[]')
      panel.setAttribute('good-options', '[{"abbr":"F","full":"Frame"},{"abbr":"P","full":"Posture"},{"abbr":"T","full":"Timing"}]')
      panel.setAttribute('bad-options', '[]')

      document.body.appendChild(panel)

      const goodSection = panel.querySelector('.good')
      expect(goodSection).toBeTruthy()
      expect(goodSection.dataset.value).toBe('F P')

      const selectedButtons = goodSection.querySelectorAll('button.selected')
      expect(selectedButtons).toHaveLength(2)

      const selectedAbbrs = Array.from(selectedButtons).map(btn => btn.querySelector('abbr').textContent)
      expect(selectedAbbrs).toContain('F')
      expect(selectedAbbrs).toContain('P')
    })

    it('renders bad feedback buttons', () => {
      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('bad', 'T')
      panel.setAttribute('overall-options', '[]')
      panel.setAttribute('good-options', '[]')
      panel.setAttribute('bad-options', '[{"abbr":"F","full":"Frame"},{"abbr":"T","full":"Timing"}]')

      document.body.appendChild(panel)

      const badSection = panel.querySelector('.bad')
      expect(badSection).toBeTruthy()

      const selectedButton = badSection.querySelector('button.selected')
      expect(selectedButton).toBeTruthy()
      expect(selectedButton.querySelector('abbr').textContent).toBe('T')
    })

    it('renders all three sections when provided', () => {
      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('value', '3')
      panel.setAttribute('good', 'F')
      panel.setAttribute('bad', 'T')
      panel.setAttribute('overall-options', '["1","2","3","4","5"]')
      panel.setAttribute('good-options', '[{"abbr":"F","full":"Frame"}]')
      panel.setAttribute('bad-options', '[{"abbr":"T","full":"Timing"}]')

      document.body.appendChild(panel)

      expect(panel.querySelector('.value')).toBeTruthy()
      expect(panel.querySelector('.good')).toBeTruthy()
      expect(panel.querySelector('.bad')).toBeTruthy()
    })

    it('handles empty selections', () => {
      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('value', '')
      panel.setAttribute('good', '')
      panel.setAttribute('bad', '')
      panel.setAttribute('overall-options', '["1","2","3"]')
      panel.setAttribute('good-options', '[{"abbr":"F","full":"Frame"}]')
      panel.setAttribute('bad-options', '[{"abbr":"T","full":"Timing"}]')

      document.body.appendChild(panel)

      const selectedButtons = panel.querySelectorAll('button.selected')
      expect(selectedButtons).toHaveLength(0)
    })
  })

  describe('Interactions', () => {
    it('calls saveScore when value button clicked', async () => {
      const { heatDataManager } = await import('../../app/javascript/helpers/heat_data_manager.js')
      heatDataManager.saveScore = vi.fn(() => Promise.resolve({ value: '4' }))

      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('slot', '1')
      panel.setAttribute('value', '3')
      panel.setAttribute('overall-options', '["1","2","3","4","5"]')
      panel.setAttribute('good-options', '[]')
      panel.setAttribute('bad-options', '[]')

      document.body.appendChild(panel)

      const buttons = panel.querySelectorAll('.value button')
      const button4 = Array.from(buttons).find(btn => btn.querySelector('abbr').textContent === '4')

      await button4.click()

      // Wait for async operations
      await new Promise(resolve => setTimeout(resolve, 10))

      const call = heatDataManager.saveScore.mock.calls[0]
      expect(call[0]).toBe(55)
      expect(call[1]).toEqual({ heat: 100, slot: 1, value: '4' })
      expect(call[2]).toHaveProperty('value', '3')
    })

    it('calls saveScore when good feedback button clicked', async () => {
      const { heatDataManager } = await import('../../app/javascript/helpers/heat_data_manager.js')
      heatDataManager.saveScore = vi.fn(() => Promise.resolve({ good: 'F P T' }))

      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('good', 'F P')
      panel.setAttribute('overall-options', '[]')
      panel.setAttribute('good-options', '[{"abbr":"F","full":"Frame"},{"abbr":"P","full":"Posture"},{"abbr":"T","full":"Timing"}]')
      panel.setAttribute('bad-options', '[]')

      document.body.appendChild(panel)

      const buttons = panel.querySelectorAll('.good button')
      const buttonT = Array.from(buttons).find(btn => btn.querySelector('abbr').textContent === 'T')

      await buttonT.click()

      // Wait for async operations
      await new Promise(resolve => setTimeout(resolve, 10))

      const call = heatDataManager.saveScore.mock.calls[0]
      expect(call[0]).toBe(55)
      expect(call[1]).toEqual({ heat: 100, slot: null, good: 'T' })
      expect(call[2]).toHaveProperty('good', 'F P')
    })

    it('updates UI when server responds with new values', async () => {
      const { heatDataManager } = await import('../../app/javascript/helpers/heat_data_manager.js')
      heatDataManager.saveScore = vi.fn(() => Promise.resolve({ good: 'F T' }))

      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('good', 'F P')
      panel.setAttribute('overall-options', '[]')
      panel.setAttribute('good-options', '[{"abbr":"F","full":"Frame"},{"abbr":"P","full":"Posture"},{"abbr":"T","full":"Timing"}]')
      panel.setAttribute('bad-options', '[]')

      document.body.appendChild(panel)

      const buttons = panel.querySelectorAll('.good button')
      const buttonT = Array.from(buttons).find(btn => btn.querySelector('abbr').textContent === 'T')

      await buttonT.click()

      // Wait for async operations
      await new Promise(resolve => setTimeout(resolve, 10))

      // Check that F and T are selected, P is not
      const goodSection = panel.querySelector('.good')
      const selectedButtons = goodSection.querySelectorAll('button.selected')
      expect(selectedButtons).toHaveLength(2)

      const selectedAbbrs = Array.from(selectedButtons).map(btn => btn.querySelector('abbr').textContent)
      expect(selectedAbbrs).toContain('F')
      expect(selectedAbbrs).toContain('T')
      expect(selectedAbbrs).not.toContain('P')
    })

    it('dispatches score-updated event on successful save', async () => {
      const { heatDataManager } = await import('../../app/javascript/helpers/heat_data_manager.js')
      heatDataManager.saveScore = vi.fn(() => Promise.resolve({ value: '4' }))

      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('slot', '1')
      panel.setAttribute('value', '3')
      panel.setAttribute('overall-options', '["1","2","3","4","5"]')
      panel.setAttribute('good-options', '[]')
      panel.setAttribute('bad-options', '[]')

      document.body.appendChild(panel)

      let eventDetail = null
      panel.addEventListener('score-updated', (e) => {
        eventDetail = e.detail
      })

      const buttons = panel.querySelectorAll('.value button')
      const button4 = Array.from(buttons).find(btn => btn.querySelector('abbr').textContent === '4')

      await button4.click()

      // Wait for async operations
      await new Promise(resolve => setTimeout(resolve, 10))

      expect(eventDetail).toBeTruthy()
      expect(eventDetail.heat).toBe(100)
      expect(eventDetail.slot).toBe(1)
      expect(eventDetail.value).toBe('4')
    })

    it('handles null slot attribute', async () => {
      const { heatDataManager } = await import('../../app/javascript/helpers/heat_data_manager.js')
      heatDataManager.saveScore = vi.fn(() => Promise.resolve({ value: '2' }))

      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      // No slot attribute set
      panel.setAttribute('value', '1')
      panel.setAttribute('overall-options', '["1","2","3"]')
      panel.setAttribute('good-options', '[]')
      panel.setAttribute('bad-options', '[]')

      document.body.appendChild(panel)

      const buttons = panel.querySelectorAll('.value button')
      const button2 = Array.from(buttons).find(btn => btn.querySelector('abbr').textContent === '2')

      await button2.click()

      // Wait for async operations
      await new Promise(resolve => setTimeout(resolve, 10))

      const call = heatDataManager.saveScore.mock.calls[0]
      expect(call[0]).toBe(55)
      expect(call[1]).toEqual({ heat: 100, slot: null, value: '2' })
      expect(call[2]).toBeTruthy()
    })

    it('preserves current values for offline save', async () => {
      const { heatDataManager } = await import('../../app/javascript/helpers/heat_data_manager.js')
      heatDataManager.saveScore = vi.fn(() => Promise.resolve({ good: 'F T' }))

      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('value', '3')
      panel.setAttribute('good', 'F P')
      panel.setAttribute('bad', 'T')
      panel.setAttribute('overall-options', '["1","2","3","4","5"]')
      panel.setAttribute('good-options', '[{"abbr":"F","full":"Frame"},{"abbr":"P","full":"Posture"},{"abbr":"T","full":"Timing"}]')
      panel.setAttribute('bad-options', '[{"abbr":"T","full":"Timing"}]')

      document.body.appendChild(panel)

      const buttons = panel.querySelectorAll('.good button')
      const buttonT = Array.from(buttons).find(btn => btn.querySelector('abbr').textContent === 'T')

      await buttonT.click()

      // Wait for async operations
      await new Promise(resolve => setTimeout(resolve, 10))

      // Check that currentScore was passed with all three values
      const call = heatDataManager.saveScore.mock.calls[0]
      expect(call[0]).toBe(55)
      expect(call[1]).toEqual({ heat: 100, slot: null, good: 'T' })
      expect(call[2]).toHaveProperty('value', '3')
      expect(call[2]).toHaveProperty('good', 'F P')
      expect(call[2]).toHaveProperty('bad', 'T')
    })
  })

  describe('Error Handling', () => {
    it('handles invalid JSON in options gracefully', () => {
      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('overall-options', 'invalid json')
      panel.setAttribute('good-options', '[invalid')
      panel.setAttribute('bad-options', ']')

      // Should not throw
      expect(() => {
        document.body.appendChild(panel)
      }).not.toThrow()

      // Should render with empty options
      expect(panel.querySelector('.value button')).toBeFalsy()
    })

    it('handles save error gracefully', async () => {
      const { heatDataManager } = await import('../../app/javascript/helpers/heat_data_manager.js')
      heatDataManager.saveScore = vi.fn(() => Promise.reject(new Error('Network error')))

      const panel = document.createElement('feedback-panel')
      panel.setAttribute('judge-id', '55')
      panel.setAttribute('heat', '100')
      panel.setAttribute('value', '3')
      panel.setAttribute('overall-options', '["1","2","3"]')
      panel.setAttribute('good-options', '[]')
      panel.setAttribute('bad-options', '[]')

      document.body.appendChild(panel)

      const buttons = panel.querySelectorAll('.value button')
      const button2 = Array.from(buttons).find(btn => btn.querySelector('abbr').textContent === '2')

      // Should not throw
      await expect((async () => {
        await button2.click()
        await new Promise(resolve => setTimeout(resolve, 10))
      })()).resolves.not.toThrow()
    })
  })
})
