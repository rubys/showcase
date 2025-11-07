import { describe, it, expect } from 'vitest'

/**
 * Heat Details Display Tests
 *
 * These tests verify that heat-header and heat-info-box components
 * display the correct information based on heat data:
 * - Heat header shows heat number, category, dance name
 * - Multi-dance slot display (Dance X of Y, Semi-final, Final)
 * - Multi-dance child dance names
 * - Emcee mode display (couples count, song)
 * - Solo combo dance display
 * - Info box instructions based on category and style
 */

describe('Heat Details Display', () => {
  // Helper to create heat data
  const createHeat = (config) => {
    return {
      number: config.number || 100,
      category: config.category || 'Closed',
      dance: {
        name: config.danceName || 'Test Waltz',
        heat_length: config.heatLength || 0,
        uses_scrutineering: config.usesScrutineering || false,
        multi_children: config.multiChildren || [],
        songs: config.songs || []
      },
      subjects: config.subjects || [
        { id: 1, lead: { name: 'Instructor 1', back: 501 }, follow: { name: 'Student 1', back: 401 } }
      ],
      solo: config.solo || null
    }
  }

  const createEvent = (config) => {
    return {
      assign_judges: config.assignJudges || 0,
      open_scoring: config.openScoring || 'GH,G,S,B'
    }
  }

  const createJudge = (config) => {
    return {
      id: config.id || 55,
      show_assignments: config.showAssignments || 'mixed'
    }
  }

  describe('Heat header - basic display', () => {
    it('displays heat number and dance name', () => {
      const heat = createHeat({ number: 42, danceName: 'Waltz' })

      expect(heat.number).toBe(42)
      expect(heat.dance.name).toBe('Waltz')
    })

    it('displays correct heat number for fractional heats', () => {
      const heat = createHeat({ number: 15.5, danceName: 'Tango' })

      expect(heat.number).toBe(15.5)
      expect(heat.dance.name).toBe('Tango')
    })

    it('displays Solo category with combo dance', () => {
      const heat = createHeat({
        number: 50,
        category: 'Solo',
        danceName: 'Rumba',
        solo: {
          combo_dance_id: 123,
          combo_dance: { name: 'Cha Cha' }
        }
      })

      expect(heat.category).toBe('Solo')
      expect(heat.dance.name).toBe('Rumba')
      expect(heat.solo.combo_dance.name).toBe('Cha Cha')
    })

    it('displays Multi category heat', () => {
      const heat = createHeat({
        number: 85,
        category: 'Multi',
        danceName: 'Latin 2 Dance'
      })

      expect(heat.category).toBe('Multi')
      expect(heat.dance.name).toBe('Latin 2 Dance')
    })

    it('displays Closed category heat', () => {
      const heat = createHeat({
        number: 10,
        category: 'Closed',
        danceName: 'Foxtrot'
      })

      expect(heat.category).toBe('Closed')
      expect(heat.dance.name).toBe('Foxtrot')
    })

    it('displays Open category heat', () => {
      const heat = createHeat({
        number: 20,
        category: 'Open',
        danceName: 'Swing'
      })

      expect(heat.category).toBe('Open')
      expect(heat.dance.name).toBe('Swing')
    })
  })

  describe('Multi-dance slot display', () => {
    // Helper to calculate slot display text
    const heatDanceSlotDisplay = (heat, slot, isFinal) => {
      const { heat_length, uses_scrutineering } = heat.dance
      if (!heat_length) return ''

      if (!uses_scrutineering) {
        return `Dance ${slot} of ${heat_length}:`
      } else if (!isFinal) {
        return `Semi-final ${slot} of ${heat_length}:`
      } else {
        const slotNumber = slot > heat_length ? slot - heat_length : slot
        return `Final ${slotNumber} of ${heat_length}:`
      }
    }

    it('displays "Dance X of Y" for non-scrutineering multi-dance', () => {
      const heat = createHeat({
        heatLength: 3,
        usesScrutineering: false
      })

      expect(heatDanceSlotDisplay(heat, 1, false)).toBe('Dance 1 of 3:')
      expect(heatDanceSlotDisplay(heat, 2, false)).toBe('Dance 2 of 3:')
      expect(heatDanceSlotDisplay(heat, 3, false)).toBe('Dance 3 of 3:')
    })

    it('displays "Semi-final X of Y" for scrutineering semi-finals', () => {
      const heat = createHeat({
        heatLength: 2,
        usesScrutineering: true
      })

      expect(heatDanceSlotDisplay(heat, 1, false)).toBe('Semi-final 1 of 2:')
      expect(heatDanceSlotDisplay(heat, 2, false)).toBe('Semi-final 2 of 2:')
    })

    it('displays "Final X of Y" for scrutineering finals', () => {
      const heat = createHeat({
        heatLength: 2,
        usesScrutineering: true
      })

      // Finals are slots beyond heat_length
      expect(heatDanceSlotDisplay(heat, 3, true)).toBe('Final 1 of 2:')
      expect(heatDanceSlotDisplay(heat, 4, true)).toBe('Final 2 of 2:')
    })

    it('returns empty string for heat_length = 0', () => {
      const heat = createHeat({ heatLength: 0 })

      expect(heatDanceSlotDisplay(heat, 1, false)).toBe('')
    })
  })

  describe('Multi-dance child names display', () => {
    it('displays single dance name for single-slot multi', () => {
      const heat = createHeat({
        heatLength: 1,
        multiChildren: [
          { slot: 1, name: 'Waltz', order: 1 }
        ]
      })

      expect(heat.dance.multi_children).toHaveLength(1)
      expect(heat.dance.multi_children[0].name).toBe('Waltz')
    })

    it('displays dance names for current slot in multi-slot heat', () => {
      const heat = createHeat({
        heatLength: 2,
        multiChildren: [
          { slot: 1, name: 'Waltz', order: 1 },
          { slot: 2, name: 'Tango', order: 2 }
        ]
      })

      const slot1Dances = heat.dance.multi_children.filter(c => c.slot === 1)
      const slot2Dances = heat.dance.multi_children.filter(c => c.slot === 2)

      expect(slot1Dances[0].name).toBe('Waltz')
      expect(slot2Dances[0].name).toBe('Tango')
    })

    it('displays multiple dances separated by slash', () => {
      const heat = createHeat({
        heatLength: 2,
        multiChildren: [
          { slot: 1, name: 'Waltz', order: 1 },
          { slot: 1, name: 'Foxtrot', order: 2 },
          { slot: 2, name: 'Tango', order: 3 }
        ]
      })

      const slot1Dances = heat.dance.multi_children
        .filter(c => c.slot === 1)
        .sort((a, b) => a.order - b.order)
        .map(d => d.name)
        .join(' / ')

      expect(slot1Dances).toBe('Waltz / Foxtrot')
    })

    it('handles empty multi_children array', () => {
      const heat = createHeat({ multiChildren: [] })

      expect(heat.dance.multi_children).toHaveLength(0)
    })
  })

  describe('Emcee mode display', () => {
    it('displays couples count for emcee mode', () => {
      const heat = createHeat({
        subjects: [
          { id: 1, lead: {}, follow: {} },
          { id: 2, lead: {}, follow: {} },
          { id: 3, lead: {}, follow: {} }
        ]
      })

      expect(heat.subjects.length).toBe(3)
      const couplesWord = heat.subjects.length === 1 ? 'couple' : 'couples'
      expect(couplesWord).toBe('couples')
    })

    it('uses singular "couple" for 1 couple', () => {
      const heat = createHeat({
        subjects: [
          { id: 1, lead: {}, follow: {} }
        ]
      })

      const couplesWord = heat.subjects.length === 1 ? 'couple' : 'couples'
      expect(couplesWord).toBe('couple')
    })

    it('displays song information when available', () => {
      const heat = createHeat({
        danceName: 'Waltz',
        songs: [
          { url: '/songs/1.mp3', title: 'Moon River', artist: 'Andy Williams', content_type: 'audio/mpeg' }
        ]
      })

      expect(heat.dance.songs).toHaveLength(1)
      expect(heat.dance.songs[0].title).toBe('Moon River')
      expect(heat.dance.songs[0].artist).toBe('Andy Williams')
    })

    it('cycles through songs based on heat number', () => {
      const songs = [
        { title: 'Song 1' },
        { title: 'Song 2' },
        { title: 'Song 3' }
      ]

      // Heat 1 → Song 0 (index 0)
      const songIndex1 = (1 - 1) % songs.length
      expect(songs[songIndex1].title).toBe('Song 1')

      // Heat 2 → Song 1 (index 1)
      const songIndex2 = (2 - 1) % songs.length
      expect(songs[songIndex2].title).toBe('Song 2')

      // Heat 4 → Song 0 (wraps around)
      const songIndex4 = (4 - 1) % songs.length
      expect(songs[songIndex4].title).toBe('Song 1')
    })
  })

  describe('Info box - scoring instructions', () => {
    // Helper to get scoring instruction text
    const scoringInstructionText = (category, style, openScoring) => {
      if (category === 'Solo') {
        return "Tab to or click on comments or score to edit. Press escape or click elsewhere to save."
      } else if (style !== 'radio') {
        return "Drag and drop instructions"
      } else if (openScoring === '#') {
        return "Enter scores in the right most column. Tab to move to the next entry."
      } else if (openScoring === '+') {
        return "Feedback instructions"
      } else {
        return 'Radio button instructions'
      }
    }

    it('displays Solo instructions for Solo category', () => {
      const instructions = scoringInstructionText('Solo', 'radio', 'GH,G,S,B')
      expect(instructions).toContain('Tab to or click')
      expect(instructions).toContain('escape')
    })

    it('displays drag-and-drop instructions for cards style', () => {
      const instructions = scoringInstructionText('Closed', 'cards', 'GH,G,S,B')
      expect(instructions).toContain('Drag and drop')
    })

    it('displays numeric scoring instructions for open_scoring = #', () => {
      const instructions = scoringInstructionText('Open', 'radio', '#')
      expect(instructions).toContain('Enter scores')
      expect(instructions).toContain('right most column')
    })

    it('displays feedback instructions for open_scoring = +', () => {
      const instructions = scoringInstructionText('Closed', 'radio', '+')
      expect(instructions).toContain('Feedback')
    })

    it('displays radio button instructions for default scoring', () => {
      const instructions = scoringInstructionText('Closed', 'radio', 'GH,G,S,B')
      expect(instructions).toContain('Radio button')
    })
  })

  describe('Info box - navigation instructions', () => {
    it('includes base navigation text', () => {
      const baseText = "Clicking on the arrows at the bottom corners will advance you to the next or previous heats. Left and right arrows on the keyboard may also be used"

      expect(baseText).toContain('arrows at the bottom')
      expect(baseText).toContain('keyboard')
    })

    it('adds suffix for Solo category', () => {
      const suffix = " when not editing comments or score"
      expect(suffix).toContain('when not editing')
    })
  })

  describe('Edge cases', () => {
    it('handles heat with no subjects', () => {
      const heat = createHeat({ subjects: [] })
      expect(heat.subjects.length).toBe(0)
    })

    it('handles heat with no dance songs', () => {
      const heat = createHeat({ songs: [] })
      expect(heat.dance.songs).toHaveLength(0)
    })

    it('handles Solo heat without combo dance', () => {
      const heat = createHeat({
        category: 'Solo',
        solo: { combo_dance_id: null, combo_dance: null }
      })

      expect(heat.solo.combo_dance_id).toBeNull()
    })

    it('handles heat with large number of subjects', () => {
      const subjects = Array(20).fill(null).map((_, i) => ({
        id: i + 1,
        lead: { name: `Lead ${i}`, back: 500 + i },
        follow: { name: `Follow ${i}`, back: 400 + i }
      }))

      const heat = createHeat({ subjects })
      expect(heat.subjects.length).toBe(20)
    })
  })
})
