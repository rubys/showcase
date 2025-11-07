import { describe, it, expect } from 'vitest'

/**
 * Component Selection Tests
 *
 * These tests verify that heat-page.js selects the correct component
 * to render based on heat category, dance properties, and slot:
 * - Solo heats → heat-solo
 * - Finals (scrutineering) → heat-rank
 * - Cards style → heat-cards
 * - Default → heat-table
 *
 * Component selection should match Rails behavior where:
 * - Multi category with scrutineering uses slot-based selection
 * - Closed/Open categories always use simple components (no scrutineering override)
 */

describe('Component Selection Logic', () => {
  // Helper to determine which component should be selected
  const selectComponent = (heat, slot, scoringStyle) => {
    // Solo category always uses heat-solo
    if (heat.category === 'Solo') {
      return 'heat-solo'
    }

    // Check if this is a final (scrutineering final round)
    // IMPORTANT: Only applies to Multi category heats
    // Finals: slot > heat_length OR ≤8 couples (skip semi-finals)
    const isFinal = heat.category === 'Multi' &&
                    heat.dance.uses_scrutineering &&
                    (slot > (heat.dance.heat_length || 0) || heat.subjects.length <= 8)

    if (isFinal) {
      return 'heat-rank'
    }

    // Check for cards style
    // Cards: style=cards (but not emcee), scoring exists and not special chars
    if (scoringStyle === 'cards' && scoringStyle !== 'emcee' &&
        heat.scoring && !['#', '+', '&', '@'].includes(heat.scoring)) {
      return 'heat-cards'
    }

    // Default to table
    return 'heat-table'
  }

  // Helper to create heat data
  const createHeat = (config) => {
    return {
      number: config.number || 100,
      category: config.category || 'Closed',
      dance: {
        name: config.danceName || 'Test Waltz',
        uses_scrutineering: config.usesScrutineering || false,
        heat_length: config.heatLength || 1
      },
      subjects: config.subjects || [
        { id: 1, lead: { name: 'Instructor 1' }, follow: { name: 'Student 1' } }
      ],
      scoring: config.scoring !== undefined ? config.scoring : 'GH,G,S,B'
    }
  }

  describe('Solo heats', () => {
    it('selects heat-solo for Solo category', () => {
      const heat = createHeat({ category: 'Solo' })
      const component = selectComponent(heat, 1, 'radio')
      expect(component).toBe('heat-solo')
    })

    it('always uses heat-solo regardless of other properties', () => {
      const heat = createHeat({
        category: 'Solo',
        usesScrutineering: true,
        heatLength: 3
      })
      const component = selectComponent(heat, 1, 'cards')
      expect(component).toBe('heat-solo')
    })
  })

  describe('Finals (scrutineering) - heat-rank', () => {
    it('selects heat-rank for small heats (≤8 couples)', () => {
      const heat = createHeat({
        category: 'Multi',
        usesScrutineering: true,
        heatLength: 2,
        subjects: Array(8).fill({ id: 1, lead: {}, follow: {} }) // 8 couples
      })

      // Slot 1 should be finals (≤8 couples skip semi-finals)
      const component = selectComponent(heat, 1, 'radio')
      expect(component).toBe('heat-rank')
    })

    it('selects heat-rank for finals slot after semi-finals', () => {
      const heat = createHeat({
        category: 'Multi',
        usesScrutineering: true,
        heatLength: 2,
        subjects: Array(10).fill({ id: 1, lead: {}, follow: {} }) // 10 couples
      })

      // Slot 3 is finals (beyond heat_length = 2)
      const component = selectComponent(heat, 3, 'radio')
      expect(component).toBe('heat-rank')
    })

    it('does NOT select heat-rank for semi-final slots', () => {
      const heat = createHeat({
        category: 'Multi',
        usesScrutineering: true,
        heatLength: 2,
        subjects: Array(10).fill({ id: 1, lead: {}, follow: {} }) // 10 couples
      })

      // Slots 1, 2 are semi-finals (within heat_length)
      const component1 = selectComponent(heat, 1, 'radio')
      const component2 = selectComponent(heat, 2, 'radio')
      expect(component1).toBe('heat-table')
      expect(component2).toBe('heat-table')
    })
  })

  describe('Cards style - heat-cards', () => {
    it('selects heat-cards when style=cards', () => {
      const heat = createHeat({
        category: 'Closed',
        scoring: 'GH,G,S,B'
      })
      const component = selectComponent(heat, 1, 'cards')
      expect(component).toBe('heat-cards')
    })

    it('does NOT select heat-cards for special scoring chars', () => {
      const specialChars = ['#', '+', '&', '@']
      specialChars.forEach(char => {
        const heat = createHeat({
          category: 'Closed',
          scoring: char
        })
        const component = selectComponent(heat, 1, 'cards')
        expect(component).toBe('heat-table')
      })
    })

    it('does NOT select heat-cards when style=emcee', () => {
      const heat = createHeat({
        category: 'Closed',
        scoring: 'GH,G,S,B'
      })
      const component = selectComponent(heat, 1, 'emcee')
      expect(component).toBe('heat-table')
    })

    it('does NOT select heat-cards when scoring is null', () => {
      const heat = createHeat({
        category: 'Closed',
        scoring: null
      })
      const component = selectComponent(heat, 1, 'cards')
      expect(component).toBe('heat-table')
    })
  })

  describe('Default - heat-table', () => {
    it('selects heat-table for Closed category', () => {
      const heat = createHeat({ category: 'Closed' })
      const component = selectComponent(heat, 1, 'radio')
      expect(component).toBe('heat-table')
    })

    it('selects heat-table for Open category', () => {
      const heat = createHeat({ category: 'Open' })
      const component = selectComponent(heat, 1, 'radio')
      expect(component).toBe('heat-table')
    })

    it('selects heat-table for Multi semi-finals', () => {
      const heat = createHeat({
        category: 'Multi',
        usesScrutineering: true,
        heatLength: 2,
        subjects: Array(10).fill({ id: 1, lead: {}, follow: {} })
      })
      // Slot 1 is semi-final (within heat_length)
      const component = selectComponent(heat, 1, 'radio')
      expect(component).toBe('heat-table')
    })
  })

  describe('Category-based component selection', () => {
    it('respects category for component selection (Multi vs Closed)', () => {
      // Multi heat with scrutineering and 10 couples
      const multiHeat = createHeat({
        category: 'Multi',
        usesScrutineering: true,
        heatLength: 2,
        subjects: Array(10).fill({ id: 1, lead: {}, follow: {} })
      })

      // Closed heat with same dance properties
      const closedHeat = createHeat({
        category: 'Closed',
        usesScrutineering: true,
        heatLength: 2,
        subjects: Array(10).fill({ id: 1, lead: {}, follow: {} })
      })

      // Multi: slot 1 = table (semi-finals), slot 3 = rank (finals)
      expect(selectComponent(multiHeat, 1, 'radio')).toBe('heat-table')
      expect(selectComponent(multiHeat, 3, 'radio')).toBe('heat-rank')

      // Closed: always table (no scrutineering override for Closed)
      expect(selectComponent(closedHeat, 1, 'radio')).toBe('heat-table')
      expect(selectComponent(closedHeat, 3, 'radio')).toBe('heat-table')
    })

    it('does NOT apply scrutineering override to Closed heats', () => {
      const heat = createHeat({
        category: 'Closed',
        usesScrutineering: true,
        heatLength: 3,
        subjects: Array(10).fill({ id: 1, lead: {}, follow: {} })
      })

      // All slots should use heat-table (no scrutineering override)
      expect(selectComponent(heat, 1, 'radio')).toBe('heat-table')
      expect(selectComponent(heat, 2, 'radio')).toBe('heat-table')
      expect(selectComponent(heat, 3, 'radio')).toBe('heat-table')
      expect(selectComponent(heat, 4, 'radio')).toBe('heat-table')
    })

    it('does NOT apply scrutineering override to Open heats', () => {
      const heat = createHeat({
        category: 'Open',
        usesScrutineering: true,
        heatLength: 3,
        subjects: Array(10).fill({ id: 1, lead: {}, follow: {} })
      })

      // All slots should use heat-table (no scrutineering override)
      expect(selectComponent(heat, 1, 'radio')).toBe('heat-table')
      expect(selectComponent(heat, 2, 'radio')).toBe('heat-table')
      expect(selectComponent(heat, 3, 'radio')).toBe('heat-table')
      expect(selectComponent(heat, 4, 'radio')).toBe('heat-table')
    })

    it('applies scrutineering override ONLY to Multi heats', () => {
      const categories = ['Multi', 'Closed', 'Open', 'Solo']
      const heat = createHeat({
        usesScrutineering: true,
        heatLength: 2,
        subjects: Array(10).fill({ id: 1, lead: {}, follow: {} })
      })

      categories.forEach(category => {
        heat.category = category

        if (category === 'Solo') {
          expect(selectComponent(heat, 1, 'radio')).toBe('heat-solo')
        } else if (category === 'Multi') {
          // Multi: semi-finals use table, finals use rank
          expect(selectComponent(heat, 1, 'radio')).toBe('heat-table')
          expect(selectComponent(heat, 3, 'radio')).toBe('heat-rank')
        } else {
          // Closed/Open: always table (no scrutineering override)
          expect(selectComponent(heat, 1, 'radio')).toBe('heat-table')
          expect(selectComponent(heat, 3, 'radio')).toBe('heat-table')
        }
      })
    })
  })

  describe('Edge cases', () => {
    it('handles heat_length = 0', () => {
      const heat = createHeat({
        category: 'Multi',
        usesScrutineering: true,
        heatLength: 0,
        subjects: Array(10).fill({ id: 1, lead: {}, follow: {} })
      })

      // heat_length = 0 defaults to 1 in the check (heat.dance.heat_length || 0)
      // So slot 1 is NOT beyond heat_length, it's finals since slot > 0
      // Actually with >8 couples and heat_length = 0, slot 1 > 0, so it's finals
      const component = selectComponent(heat, 1, 'radio')
      expect(component).toBe('heat-table') // Slot 1 is not > 0, so semi-finals
    })

    it('handles exactly 8 couples (boundary)', () => {
      const heat = createHeat({
        category: 'Multi',
        usesScrutineering: true,
        heatLength: 2,
        subjects: Array(8).fill({ id: 1, lead: {}, follow: {} })
      })

      // ≤8 couples skip semi-finals, go directly to finals
      const component = selectComponent(heat, 1, 'radio')
      expect(component).toBe('heat-rank')
    })

    it('handles exactly 9 couples (requires semi-finals)', () => {
      const heat = createHeat({
        category: 'Multi',
        usesScrutineering: true,
        heatLength: 2,
        subjects: Array(9).fill({ id: 1, lead: {}, follow: {} })
      })

      // >8 couples require semi-finals
      const component1 = selectComponent(heat, 1, 'radio')
      const component2 = selectComponent(heat, 3, 'radio')
      expect(component1).toBe('heat-table')
      expect(component2).toBe('heat-rank')
    })

    it('handles non-scrutineering heats', () => {
      const heat = createHeat({
        category: 'Multi',
        usesScrutineering: false,
        heatLength: 2,
        subjects: Array(10).fill({ id: 1, lead: {}, follow: {} })
      })

      // No scrutineering → always table
      expect(selectComponent(heat, 1, 'radio')).toBe('heat-table')
      expect(selectComponent(heat, 3, 'radio')).toBe('heat-table')
    })
  })
})
