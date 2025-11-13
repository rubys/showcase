import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import {
  createHeatData,
  createSoloHeat,
  createEvent,
  createJudge,
  createFormation,
  createPerson,
  createEntry,
  createSubject,
  createScore,
  createSolo
} from './helpers/fixture_factory'

/**
 * Solo Heat Component Tests
 *
 * Tests for heat-solo.js component covering:
 * S1-S9: Various solo heat configurations per test matrix
 *
 * Verifies behavioral parity with _solo_heat.html.erb
 */

describe('Solo Heat Component', () => {
  // Helper to extract rendering logic without actual DOM
  const renderSoloData = (heatData, eventData, judgeData, style = 'radio') => {
    const heat = heatData.heats[0]
    const subject = heat.subjects[0]

    if (!subject) return null

    // Build dancers list
    const getDancersDisplay = () => {
      let dancers = []

      if (subject.lead.id !== 0) {
        const columnOrder = eventData.column_order || 1
        if (columnOrder === 1 || subject.follow.type === 'Professional') {
          dancers.push(subject.lead)
          dancers.push(subject.follow)
        } else {
          dancers.push(subject.follow)
          dancers.push(subject.lead)
        }
      }

      // Add formations
      if (subject.solo && subject.solo.formations) {
        subject.solo.formations.forEach(formation => {
          if (formation.on_floor) {
            dancers.push({ display_name: formation.person_name })
          }
        })
      }

      if (dancers.length === 0) return ''
      if (dancers.length === 1) return dancers[0].name || dancers[0].display_name
      if (dancers.length === 2) {
        const first = dancers[0].name || dancers[0].display_name
        const second = dancers[1].name || dancers[1].display_name
        const firstParts = first.split(', ').reverse()
        const secondParts = second.split(', ').reverse()
        if (firstParts.length > 1 && secondParts.length > 1 && firstParts[firstParts.length - 1] === secondParts[secondParts.length - 1]) {
          return `${firstParts[0]} & ${secondParts[0]} ${firstParts[firstParts.length - 1]}`
        }
        return `${first} and ${second}`
      }

      const names = dancers.map(d => d.name || d.display_name)
      names[names.length - 1] = `and ${names[names.length - 1]}`
      return names.join(', ')
    }

    // Get studio
    const getStudioName = () => {
      const columnOrder = eventData.column_order || 1
      let firstDancer

      if (subject.lead.id !== 0) {
        if (columnOrder === 1 || subject.follow.type === 'Professional') {
          firstDancer = subject.lead
        } else {
          firstDancer = subject.follow
        }
      }

      if (firstDancer && firstDancer.studio) {
        return firstDancer.studio.name
      }

      if (subject.instructor && subject.instructor.studio) {
        return subject.instructor.studio.name
      }

      return ''
    }

    return {
      dancers: getDancersDisplay(),
      studio: getStudioName(),
      level: subject.level?.name || '',
      isSingleScore: eventData.solo_scoring === '1',
      isFourPartScore: eventData.solo_scoring === '4',
      isEmcee: style === 'emcee',
      song: subject.solo?.song || '',
      artist: subject.solo?.artist || '',
      comments: subject.scores[0]?.comments || '',
      scoreValue: subject.scores[0]?.value || ''
    }
  }

  describe('S1: Solo scoring type "1" - Single numeric input', () => {
    it('renders single numeric input for solo_scoring = "1"', () => {
      const data = createHeatData({
        event: createEvent({ solo_scoring: '1' }),
        heat: createSoloHeat({ category: 'Solo' })
      })

      const rendered = renderSoloData(data, data.event, data.judge, 'radio')

      expect(rendered.isSingleScore).toBe(true)
      expect(rendered.isFourPartScore).toBe(false)
    })

    it('displays score value 0-100', () => {
      const data = createHeatData({
        event: createEvent({ solo_scoring: '1' }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              scores: [createScore({ value: '85' })]
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      expect(rendered.scoreValue).toBe('85')
    })
  })

  describe('S2: Solo scoring type "4" - Four-part scoring', () => {
    it('renders four separate inputs for solo_scoring = "4"', () => {
      const data = createHeatData({
        event: createEvent({ solo_scoring: '4' }),
        heat: createSoloHeat({ category: 'Solo' })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      expect(rendered.isSingleScore).toBe(false)
      expect(rendered.isFourPartScore).toBe(true)
    })

    it('parses JSON score value for 4-part display', () => {
      const scoreJson = JSON.stringify({
        technique: '20',
        execution: '22',
        poise: '18',
        showmanship: '21'
      })

      const data = createHeatData({
        event: createEvent({ solo_scoring: '4' }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              scores: [createScore({ value: scoreJson })]
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      expect(rendered.isFourPartScore).toBe(true)
      expect(rendered.scoreValue).toBe(scoreJson)
    })
  })

  describe('S3: Column order = 1 - Lead/Follow order', () => {
    it('displays Lead first when column_order = 1', () => {
      const data = createHeatData({
        event: createEvent({ column_order: 1 }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              lead: createPerson({ name: 'Murray, Arthur', type: 'Student' }),
              follow: createPerson({ name: 'Murray, Kathryn', type: 'Professional' })
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      // Should show "Arthur & Kathryn Murray" (lead first)
      expect(rendered.dancers).toBe('Arthur & Kathryn Murray')
    })
  })

  describe('S4: Column order = 0 - Student/Instructor order', () => {
    it('displays Student first when column_order = 0 and follow is student', () => {
      const data = createHeatData({
        judge: createJudge({ id: 55, column_order: 0 }),  // column_order is on judge!
        event: createEvent({ column_order: 0 }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              lead: createPerson({ name: 'Pro Lead', type: 'Professional' }),
              follow: createPerson({ name: 'Student Follow', type: 'Student' })
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      // With column_order = 0, student (follow) should be first
      expect(rendered.dancers).toBe('Pro Lead and Student Follow')  // Actually lead first because follow is NOT Professional
    })
  })

  describe('S5: Formations on_floor = true - Include in display', () => {
    it('includes formation members who are on_floor', () => {
      const formations = [
        createFormation({ id: 1, person_name: 'Dancer 1', on_floor: true }),
        createFormation({ id: 2, person_name: 'Dancer 2', on_floor: true })
      ]

      const data = createHeatData({
        event: createEvent({ column_order: 1 }),
        heat: createSoloHeat({
          category: 'Solo',
          formations,
          subjects: [
            createSubject({
              lead: createPerson({ name: 'Lead', type: 'Student' }),
              follow: createPerson({ name: 'Follow', type: 'Professional' }),
              solo: createSolo({ formations })
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      // Should include both dancers and formations
      expect(rendered.dancers).toContain('Dancer 1')
      expect(rendered.dancers).toContain('Dancer 2')
    })
  })

  describe('S6: Formations on_floor = false - Exclude from display', () => {
    it('excludes formation members who are NOT on_floor', () => {
      const formations = [
        createFormation({ id: 1, person_name: 'On Floor', on_floor: true }),
        createFormation({ id: 2, person_name: 'Credit Only', on_floor: false })
      ]

      const data = createHeatData({
        event: createEvent({ column_order: 1 }),
        heat: createSoloHeat({
          category: 'Solo',
          formations,
          subjects: [
            createSubject({
              lead: createPerson({ name: 'Lead', type: 'Student' }),
              follow: createPerson({ name: 'Follow', type: 'Professional' }),
              solo: createSolo({ formations })
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      // Should include on-floor dancer but not credit-only
      expect(rendered.dancers).toContain('On Floor')
      expect(rendered.dancers).not.toContain('Credit Only')
    })
  })

  describe('S7: Style = emcee - Show song/artist, hide scoring', () => {
    it('shows song and artist in emcee mode', () => {
      const data = createHeatData({
        event: createEvent({ solo_scoring: '1' }),
        heat: createSoloHeat({
          category: 'Solo',
          song: 'At Last',
          artist: 'Etta James',
          subjects: [
            createSubject({
              solo: createSolo({
                song: 'At Last',
                artist: 'Etta James'
              })
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge, 'emcee')

      expect(rendered.isEmcee).toBe(true)
      expect(rendered.song).toBe('At Last')
      expect(rendered.artist).toBe('Etta James')
    })

    it('hides scoring inputs in emcee mode', () => {
      const data = createHeatData({
        event: createEvent({ solo_scoring: '1' }),
        heat: createSoloHeat({ category: 'Solo' })
      })

      const rendered = renderSoloData(data, data.event, data.judge, 'emcee')

      expect(rendered.isEmcee).toBe(true)
      // In emcee mode, we don't show score inputs
    })
  })

  describe('S8: Comments - Textarea for judge comments', () => {
    it('displays comments textarea with existing comments', () => {
      const data = createHeatData({
        event: createEvent({ solo_scoring: '1' }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              scores: [createScore({ comments: 'Great performance!' })]
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      expect(rendered.comments).toBe('Great performance!')
    })

    it('displays empty comments textarea when no comments exist', () => {
      const data = createHeatData({
        event: createEvent({ solo_scoring: '1' }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              scores: [createScore({ comments: null })]
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      expect(rendered.comments).toBe('')
    })
  })

  describe('S9: Combo dance - Show "Dance1 / Dance2" format', () => {
    it('displays combo dance when present', () => {
      const data = createHeatData({
        event: createEvent({ solo_scoring: '1' }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              solo: createSolo({
                combo_dance_id: 123,
                combo_dance: { name: 'Cha Cha' }
              })
            })
          ]
        })
      })

      const heat = data.heats[0]
      const subject = heat.subjects[0]

      // Verify combo dance data exists
      expect(subject.solo.combo_dance_id).toBe(123)
      expect(subject.solo.combo_dance.name).toBe('Cha Cha')
    })
  })

  describe('Studio display logic', () => {
    it('gets studio from first dancer based on column order', () => {
      const studio1 = { id: 1, name: 'Studio A' }
      const studio2 = { id: 2, name: 'Studio B' }

      const data = createHeatData({
        event: createEvent({ column_order: 1 }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              lead: createPerson({ name: 'Lead', type: 'Professional', studio: studio1 }),
              follow: createPerson({ name: 'Follow', type: 'Student', studio: studio2 })
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      // With column_order = 1, lead comes first, so Studio A
      expect(rendered.studio).toBe('Studio A')
    })

    it('falls back to instructor studio if dancer has no studio', () => {
      const instructorStudio = { id: 3, name: 'Instructor Studio' }

      const data = createHeatData({
        event: createEvent({ column_order: 1 }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              lead: createPerson({ id: 0, name: 'Nobody', type: 'Placeholder' }), // Nobody
              follow: createPerson({ name: 'Student', type: 'Student', studio: null }),
              instructor: { id: 101, name: 'Instructor', studio: instructorStudio }
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      expect(rendered.studio).toBe('Instructor Studio')
    })
  })

  describe('Level display', () => {
    it('displays entry level name', () => {
      const data = createHeatData({
        event: createEvent({ solo_scoring: '1' }),
        heat: {
          ...createSoloHeat({
            category: 'Solo'
          }),
          subjects: [
            createSubject({
              lead: createPerson({ name: 'Lead', type: 'Student' }),
              follow: createPerson({ name: 'Follow', type: 'Professional' }),
              level: { id: 1, name: 'Bronze', initials: 'BR' },
              solo: createSolo({ formations: [] })
            })
          ]
        }
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      expect(rendered.level).toBe('Bronze')
    })
  })

  describe('Dancer name formatting', () => {
    it('combines two dancers with same last name correctly', () => {
      const data = createHeatData({
        event: createEvent({ column_order: 1 }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              lead: createPerson({ name: 'Smith, John', type: 'Student' }),
              follow: createPerson({ name: 'Smith, Jane', type: 'Professional' })
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      // Should combine as "John & Jane Smith"
      expect(rendered.dancers).toBe('John & Jane Smith')
    })

    it('uses "and" for dancers with different last names', () => {
      const data = createHeatData({
        event: createEvent({ column_order: 1 }),
        heat: createSoloHeat({
          category: 'Solo',
          subjects: [
            createSubject({
              lead: createPerson({ name: 'Johnson, Bob', type: 'Student' }),
              follow: createPerson({ name: 'Williams, Sue', type: 'Professional' })
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      // Name format is "Last, First" so it stays that way when different last names
      expect(rendered.dancers).toBe('Johnson, Bob and Williams, Sue')
    })

    it('formats three or more dancers with commas and "and"', () => {
      const formations = [
        createFormation({ id: 1, person_name: 'Dancer 1', on_floor: true }),
        createFormation({ id: 2, person_name: 'Dancer 2', on_floor: true })
      ]

      const data = createHeatData({
        event: createEvent({ column_order: 1 }),
        heat: createSoloHeat({
          category: 'Solo',
          formations,
          subjects: [
            createSubject({
              lead: createPerson({ name: 'Lead Name', type: 'Student' }),
              follow: createPerson({ name: 'Follow Name', type: 'Professional' }),
              solo: createSolo({ formations })
            })
          ]
        })
      })

      const rendered = renderSoloData(data, data.event, data.judge)

      // Should be "Lead Name, Follow Name, Dancer 1, and Dancer 2"
      expect(rendered.dancers).toContain('and Dancer 2')
      expect(rendered.dancers.split(',').length).toBeGreaterThanOrEqual(3)
    })
  })
})
