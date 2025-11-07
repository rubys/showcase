import { describe, it, expect, beforeEach } from 'vitest'

/**
 * Navigation Logic Tests
 *
 * These tests verify that the SPA navigation algorithm matches the Rails behavior:
 * - Next/prev heats follow numerical order
 * - Fractional heat numbers work correctly (15 → 15.5 → 16)
 * - Slot-based navigation for Multi heats
 * - Simple navigation for Closed/Open heats
 */

describe('Heat Navigation Algorithm', () => {
  // Helper function to simulate heat data structure
  const createHeatData = (heatsConfig) => {
    return {
      heats: heatsConfig.map(config => ({
        number: config.number,
        category: config.category || 'Closed',
        dance: {
          name: config.dance || 'Test Dance',
          heat_length: config.heat_length || null,
          uses_scrutineering: config.scrutineering || false
        },
        subjects: config.subjects || [{ id: 1, lead: { name: 'Lead' }, follow: { name: 'Follow' } }]
      }))
    }
  }

  // Helper to find next heat (mimics HeatPage.navigateNext logic)
  const findNextHeat = (heats, currentNumber, currentSlot = 1) => {
    const currentHeat = heats.find(h => h.number === currentNumber)
    if (!currentHeat) return null

    // For Multi category with scrutineering, check if we need to advance slot
    if (currentHeat.category === 'Multi' && currentHeat.dance.uses_scrutineering) {
      const heatLength = currentHeat.dance.heat_length || 1
      if (currentSlot < heatLength) {
        return { number: currentNumber, slot: currentSlot + 1 }
      }
    }

    // Find next heat by number
    const sortedHeats = [...heats].sort((a, b) => a.number - b.number)
    const currentIndex = sortedHeats.findIndex(h => h.number === currentNumber)
    const nextHeat = sortedHeats[currentIndex + 1]

    return nextHeat ? { number: nextHeat.number, slot: 1 } : null
  }

  // Helper to find previous heat
  const findPrevHeat = (heats, currentNumber, currentSlot = 1) => {
    const currentHeat = heats.find(h => h.number === currentNumber)
    if (!currentHeat) return null

    // For Multi category with scrutineering, check if we need to go back a slot
    if (currentHeat.category === 'Multi' && currentHeat.dance.uses_scrutineering && currentSlot > 1) {
      return { number: currentNumber, slot: currentSlot - 1 }
    }

    // Find previous heat by number
    const sortedHeats = [...heats].sort((a, b) => a.number - b.number)
    const currentIndex = sortedHeats.findIndex(h => h.number === currentNumber)
    const prevHeat = sortedHeats[currentIndex - 1]

    if (!prevHeat) return null

    // If prev heat is Multi with scrutineering, go to its last slot
    if (prevHeat.category === 'Multi' && prevHeat.dance.uses_scrutineering) {
      const heatLength = prevHeat.dance.heat_length || 1
      return { number: prevHeat.number, slot: heatLength }
    }

    return { number: prevHeat.number, slot: 1 }
  }

  describe('Simple numerical navigation', () => {
    it('navigates to numerically next heat across categories', () => {
      const data = createHeatData([
        { number: 15, category: 'Open' },
        { number: 16, category: 'Closed' },
        { number: 17, category: 'Open' }
      ])

      const next = findNextHeat(data.heats, 15)
      expect(next.number).toBe(16)
      expect(next.slot).toBe(1)

      // Should not skip to 17 even though same category
      const next2 = findNextHeat(data.heats, 16)
      expect(next2.number).toBe(17)
    })

    it('navigates to numerically previous heat across categories', () => {
      const data = createHeatData([
        { number: 15, category: 'Open' },
        { number: 16, category: 'Closed' },
        { number: 17, category: 'Open' }
      ])

      const prev = findPrevHeat(data.heats, 17)
      expect(prev.number).toBe(16)
      expect(prev.slot).toBe(1)

      // Should not skip to 15 even though same category
      const prev2 = findPrevHeat(data.heats, 16)
      expect(prev2.number).toBe(15)
    })
  })

  describe('Fractional heat numbers', () => {
    it('handles fractional heats in correct order 15 → 15.5 → 16', () => {
      const data = createHeatData([
        { number: 15 },
        { number: 15.5 },
        { number: 16 }
      ])

      // 15 → 15.5
      const next1 = findNextHeat(data.heats, 15)
      expect(next1.number).toBe(15.5)

      // 15.5 → 16
      const next2 = findNextHeat(data.heats, 15.5)
      expect(next2.number).toBe(16)
    })

    it('navigates backwards through fractional heats 16 → 15.5 → 15', () => {
      const data = createHeatData([
        { number: 15 },
        { number: 15.5 },
        { number: 16 }
      ])

      // 16 → 15.5
      const prev1 = findPrevHeat(data.heats, 16)
      expect(prev1.number).toBe(15.5)

      // 15.5 → 15
      const prev2 = findPrevHeat(data.heats, 15.5)
      expect(prev2.number).toBe(15)
    })

    it('handles multiple fractional heats', () => {
      const data = createHeatData([
        { number: 10 },
        { number: 10.1 },
        { number: 10.5 },
        { number: 10.9 },
        { number: 11 }
      ])

      const next1 = findNextHeat(data.heats, 10)
      expect(next1.number).toBe(10.1)

      const next2 = findNextHeat(data.heats, 10.1)
      expect(next2.number).toBe(10.5)

      const next3 = findNextHeat(data.heats, 10.5)
      expect(next3.number).toBe(10.9)

      const next4 = findNextHeat(data.heats, 10.9)
      expect(next4.number).toBe(11)
    })
  })

  describe('Slot-based navigation for Multi heats', () => {
    it('advances slots within Multi heat before moving to next heat', () => {
      const data = createHeatData([
        { number: 85, category: 'Multi', scrutineering: true, heat_length: 2 },
        { number: 86, category: 'Closed' }
      ])

      // Heat 85, slot 1 → Heat 85, slot 2
      const next1 = findNextHeat(data.heats, 85, 1)
      expect(next1.number).toBe(85)
      expect(next1.slot).toBe(2)

      // Heat 85, slot 2 → Heat 86, slot 1
      const next2 = findNextHeat(data.heats, 85, 2)
      expect(next2.number).toBe(86)
      expect(next2.slot).toBe(1)
    })

    it('goes back to previous slot within Multi heat', () => {
      const data = createHeatData([
        { number: 85, category: 'Multi', scrutineering: true, heat_length: 3 }
      ])

      // Heat 85, slot 3 → Heat 85, slot 2
      const prev1 = findPrevHeat(data.heats, 85, 3)
      expect(prev1.number).toBe(85)
      expect(prev1.slot).toBe(2)

      // Heat 85, slot 2 → Heat 85, slot 1
      const prev2 = findPrevHeat(data.heats, 85, 2)
      expect(prev2.number).toBe(85)
      expect(prev2.slot).toBe(1)
    })

    it('navigates from Closed heat to Multi heat last slot when going back', () => {
      const data = createHeatData([
        { number: 84, category: 'Multi', scrutineering: true, heat_length: 3 },
        { number: 85, category: 'Closed' }
      ])

      // Heat 85 (Closed) → Heat 84, slot 3 (last slot of Multi)
      const prev = findPrevHeat(data.heats, 85, 1)
      expect(prev.number).toBe(84)
      expect(prev.slot).toBe(3)
    })

    it('uses simple navigation for Multi heat without scrutineering', () => {
      const data = createHeatData([
        { number: 85, category: 'Multi', scrutineering: false },
        { number: 86, category: 'Closed' }
      ])

      // Multi without scrutineering → simple navigation
      const next = findNextHeat(data.heats, 85, 1)
      expect(next.number).toBe(86)
      expect(next.slot).toBe(1)
    })
  })

  describe('Simple navigation for Closed/Open heats', () => {
    it('uses simple navigation for Closed heats even with scrutineering dance', () => {
      const data = createHeatData([
        { number: 82, category: 'Closed', scrutineering: true, heat_length: 2 },
        { number: 83, category: 'Closed' }
      ])

      // Closed category → simple navigation despite scrutineering
      const next = findNextHeat(data.heats, 82, 1)
      expect(next.number).toBe(83)
      expect(next.slot).toBe(1)
    })

    it('uses simple navigation for Open heats even with scrutineering dance', () => {
      const data = createHeatData([
        { number: 87, category: 'Open', scrutineering: true, heat_length: 3 },
        { number: 88, category: 'Open' }
      ])

      // Open category → simple navigation despite scrutineering
      const next = findNextHeat(data.heats, 87, 1)
      expect(next.number).toBe(88)
      expect(next.slot).toBe(1)
    })
  })

  describe('Edge cases', () => {
    it('returns null when at last heat going forward', () => {
      const data = createHeatData([
        { number: 99 },
        { number: 100 }
      ])

      const next = findNextHeat(data.heats, 100)
      expect(next).toBeNull()
    })

    it('returns null when at first heat going backward', () => {
      const data = createHeatData([
        { number: 1 },
        { number: 2 }
      ])

      const prev = findPrevHeat(data.heats, 1)
      expect(prev).toBeNull()
    })

    it('handles heat not found', () => {
      const data = createHeatData([
        { number: 10 }
      ])

      const next = findNextHeat(data.heats, 999)
      expect(next).toBeNull()
    })

    it('handles heat_length = 1 (no slots)', () => {
      const data = createHeatData([
        { number: 50, category: 'Multi', scrutineering: true, heat_length: 1 },
        { number: 51, category: 'Closed' }
      ])

      // heat_length = 1 means no slot advancement
      const next = findNextHeat(data.heats, 50, 1)
      expect(next.number).toBe(51)
    })
  })

  describe('Heat list ordering', () => {
    it('sorts heats in numerical order', () => {
      const data = createHeatData([
        { number: 25 },
        { number: 15 },
        { number: 16 }
      ])

      const sorted = [...data.heats].sort((a, b) => a.number - b.number)
      expect(sorted.map(h => h.number)).toEqual([15, 16, 25])
    })

    it('sorts fractional heats correctly', () => {
      const data = createHeatData([
        { number: 16 },
        { number: 15.5 },
        { number: 15 },
        { number: 15.1 }
      ])

      const sorted = [...data.heats].sort((a, b) => a.number - b.number)
      expect(sorted.map(h => h.number)).toEqual([15, 15.1, 15.5, 16])
    })
  })
})
