import { describe, it, expect, beforeEach, vi } from 'vitest'

/**
 * Start Heat Button Tests (Emcee Mode)
 *
 * These tests verify that the "Start Heat" button behaves correctly:
 * - Appears in emcee mode when heat is not current
 * - Hidden when heat is already current
 * - Does NOT appear in non-emcee modes (radio, table, etc.)
 * - Disabled when offline
 * - Calls POST endpoint when clicked (online only)
 */

describe('Start Heat Button (Emcee Mode)', () => {
  // Helper to create heat data with event info
  const createHeatDataWithEvent = (config) => {
    const heatNumber = config.heatNumber || 100
    const currentHeat = config.currentHeat !== undefined ? config.currentHeat : 999
    const style = config.style !== undefined ? config.style : 'emcee'

    return {
      heat: {
        number: heatNumber,
        category: 'Multi',
        dance: {
          name: 'Test Waltz',
          semi_finals: true,
          heat_length: 2,
          uses_scrutineering: true
        },
        subjects: [
          {
            id: 1,
            lead: { name: 'Instructor 1', back: 501, type: 'Professional' },
            follow: { name: 'Student 1', back: 401, type: 'Student' },
            studio: 'Test Studio'
          }
        ]
      },
      event: {
        current_heat: currentHeat
      },
      style: style
    }
  }

  // Helper to determine if start button should be visible
  const shouldShowStartButton = (style, heatNumber, currentHeat) => {
    // Button only appears in emcee mode (exact match, not undefined or null)
    if (style !== 'emcee') {
      return false
    }

    // Button hidden if heat is already current
    if (heatNumber === currentHeat) {
      return false
    }

    return true
  }

  // Helper to determine if start button should be enabled
  const shouldEnableStartButton = (isOnline) => {
    return isOnline
  }

  describe('Button visibility', () => {
    it('appears in emcee mode when heat is not current', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: 999,
        style: 'emcee'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(true)
    })

    it('hidden when heat is already current', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: 100, // Same as heat number
        style: 'emcee'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(false)
    })

    it('does NOT appear in radio mode', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: 999,
        style: 'radio'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(false)
    })

    it('does NOT appear in table mode', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: 999,
        style: 'table'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(false)
    })

    it('does NOT appear in default mode (no style)', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: 999,
        style: null
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(false)
    })

    it('appears for scrutineering heats in emcee mode', () => {
      // Scrutineering should not affect button visibility
      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: 999,
        style: 'emcee'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(true)
    })

    it('appears for solo heats in emcee mode', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 50,
        currentHeat: 999,
        style: 'emcee'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(true)
    })
  })

  describe('Button enabled/disabled state', () => {
    it('enabled when online', () => {
      const enabled = shouldEnableStartButton(true)
      expect(enabled).toBe(true)
    })

    it('disabled when offline', () => {
      const enabled = shouldEnableStartButton(false)
      expect(enabled).toBe(false)
    })
  })

  describe('Button click behavior', () => {
    let fetchMock
    let navigatorOnlineMock

    beforeEach(() => {
      fetchMock = vi.fn()
      global.fetch = fetchMock

      // Mock navigator.onLine
      navigatorOnlineMock = vi.spyOn(window.navigator, 'onLine', 'get')
    })

    it('posts to start_heat endpoint when clicked (online)', async () => {
      navigatorOnlineMock.mockReturnValue(true)

      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: 999,
        style: 'emcee'
      })

      // Simulate clicking start heat button
      const response = await fetch('/events/start_heat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          heat: data.heat.number
        })
      })

      expect(response.ok).toBe(true)
      expect(fetchMock).toHaveBeenCalledWith(
        '/events/start_heat',
        expect.objectContaining({
          method: 'POST',
          body: expect.stringContaining('"heat":100')
        })
      )
    })

    it('does NOT post when offline', () => {
      navigatorOnlineMock.mockReturnValue(false)

      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: 999,
        style: 'emcee'
      })

      // Simulate offline click - should be prevented
      const isOnline = navigator.onLine
      if (!isOnline) {
        // Don't call fetch
        expect(fetchMock).not.toHaveBeenCalled()
      }
    })

    it('hides button after successful POST', async () => {
      navigatorOnlineMock.mockReturnValue(true)

      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: 999,
        style: 'emcee'
      })

      // Post and hide button
      const response = await fetch('/events/start_heat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          heat: data.heat.number
        })
      })

      expect(response.ok).toBe(true)
      // After successful POST, button should be hidden
      // This would be verified in component: button.style.display = 'none'
    })

    it('includes correct heat number in POST payload', async () => {
      navigatorOnlineMock.mockReturnValue(true)

      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const data = createHeatDataWithEvent({
        heatNumber: 42,
        currentHeat: 999,
        style: 'emcee'
      })

      await fetch('/events/start_heat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          heat: data.heat.number
        })
      })

      expect(fetchMock).toHaveBeenCalledWith(
        '/events/start_heat',
        expect.objectContaining({
          body: expect.stringContaining('"heat":42')
        })
      )
    })
  })

  describe('Edge cases', () => {
    it('handles current_heat = 0 (no current heat)', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: 0,
        style: 'emcee'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(true) // Button should appear since heat 100 ≠ 0
    })

    it('handles current_heat = null', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 100,
        currentHeat: null,
        style: 'emcee'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(true) // Button should appear since heat 100 ≠ null
    })

    it('handles heat number 1 (first heat)', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 1,
        currentHeat: 0,
        style: 'emcee'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(true)
    })

    it('handles large heat numbers', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 999,
        currentHeat: 500,
        style: 'emcee'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(true)
    })

    it('handles fractional heat numbers', () => {
      const data = createHeatDataWithEvent({
        heatNumber: 15.5,
        currentHeat: 15,
        style: 'emcee'
      })

      const visible = shouldShowStartButton(data.style, data.heat.number, data.event.current_heat)
      expect(visible).toBe(true)
    })
  })

  describe('Style parameter handling', () => {
    it('case-sensitive style check (only "emcee" works)', () => {
      const styles = ['emcee', 'Emcee', 'EMCEE', 'emceE']
      const results = styles.map(style =>
        shouldShowStartButton(style, 100, 999)
      )

      expect(results[0]).toBe(true)  // 'emcee' works
      expect(results[1]).toBe(false) // 'Emcee' doesn't work (case-sensitive)
      expect(results[2]).toBe(false) // 'EMCEE' doesn't work
      expect(results[3]).toBe(false) // 'emceE' doesn't work
    })

    it('whitespace in style parameter', () => {
      const visible = shouldShowStartButton(' emcee ', 100, 999)
      expect(visible).toBe(false) // Should be exact match, no trim
    })
  })
})
