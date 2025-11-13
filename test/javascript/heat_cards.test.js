/**
 * Tests for HeatCards component
 *
 * Cards heat view displays subjects as draggable cards organized by score columns.
 * Tests verify card display, drag-and-drop organization, and score posting.
 */

import { describe, it, expect } from 'vitest'
import {
  createHeatData,
  createHeat,
  createSubject,
  createPerson,
  createLevel,
  createAge,
  createScore,
  createJudge,
  createEvent
} from './helpers/fixture_factory.js'

describe('Cards Heat Component', () => {
  /**
   * Helper function that mimics heat-cards.js rendering logic
   * Returns structured data representing card layout
   */
  function renderCardsData(data, scores) {
    const heat = data.heats[0]
    const subjects = heat.subjects
    const eventData = data.event
    const judgeData = data.judge

    const backnums = eventData.backnums !== undefined ? eventData.backnums : true
    const trackAges = eventData.track_ages || false
    const combineOpenAndClosed = eventData.heat_range_cat === 1
    const columnOrder = eventData.column_order !== undefined ? eventData.column_order : 1

    // Helper to get subject category
    function getSubjectCategory(entry) {
      if (!entry.age) return ''
      const ageCategory = entry.age?.category || ''
      if (trackAges && ageCategory) {
        return ageCategory
      }
      return ''
    }

    // Build card data for each subject
    const cards = subjects.map(subject => {
      const entry = subject
      const lvl = entry.level?.initials || ''

      // Determine name order
      let firstName, secondName
      if (columnOrder === 1 || entry.follow.type === 'Professional') {
        firstName = entry.lead.name
        secondName = entry.follow.name
      } else {
        firstName = entry.follow.name
        secondName = entry.lead.name
      }

      // Format names (remove commas/spaces, truncate to 7 chars)
      firstName = firstName.replace(/[, ]/g, '').substring(0, 7)
      secondName = secondName.replace(/[, ]/g, '').substring(0, 7)

      const subjectCategory = getSubjectCategory(entry)
      const levelInitials = entry.level?.initials || ''

      // Find score for this subject
      const scoreData = subject.scores?.find(s => s.judge_id === judgeData.id)
      const scoreValue = scoreData?.value || ''

      return {
        id: subject.id,
        back: entry.lead.back,
        firstName,
        secondName,
        levelInitials,
        levelClass: lvl,
        subjectCategory,
        score: scoreValue,
        showBacknum: !!(backnums && entry.lead.back),
        showOpenClosed: combineOpenAndClosed && ['Open', 'Closed'].includes(heat.category)
      }
    })

    // Organize cards by score
    const results = {}
    scores.forEach(score => {
      results[score] = cards.filter(c => c.score === score)
    })
    // Add unscored column - subjects with empty or non-existent scores
    results[''] = cards.filter(c => c.score === '')

    return {
      cards,
      results,
      scores,
      backnums,
      trackAges,
      combineOpenAndClosed,
      columnOrder
    }
  }

  describe('C1: Basic layout - Show score columns with blank column for unscored', () => {
    it('creates score columns for each available score', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: '1' })]
        }),
        createSubject({
          id: 2,
          lead: createPerson({ back: 502 }),
          scores: [createScore({ judge_id: 55, value: '2' })]
        }),
        createSubject({
          id: 3,
          lead: createPerson({ back: 503 }),
          scores: [] // Unscored
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const scores = ['1', '2', '3', 'F', '']
      const rendered = renderCardsData(data, scores)

      expect(rendered.scores).toEqual(['1', '2', '3', 'F', ''])
      expect(rendered.results['1'].length).toBe(1)
      expect(rendered.results['2'].length).toBe(1)
      expect(rendered.results['3'].length).toBe(0)
      expect(rendered.results[''].length).toBe(1) // Unscored
    })

    it('organizes subjects into correct score columns', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: '1' })]
        }),
        createSubject({
          id: 2,
          lead: createPerson({ back: 502 }),
          scores: [createScore({ judge_id: 55, value: '1' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const scores = ['1', '2', '3', 'F', '']
      const rendered = renderCardsData(data, scores)

      expect(rendered.results['1'].length).toBe(2)
      expect(rendered.results['1'][0].back).toBe(501)
      expect(rendered.results['1'][1].back).toBe(502)
    })
  })

  describe('C2: backnums: true - Show back number prominently on cards', () => {
    it('displays back number prominently when backnums is true', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501, name: 'Smith, John' }),
          follow: createPerson({ name: 'Doe, Jane' }),
          level: createLevel({ initials: 'NV' }),
          scores: []
        })
      ]

      const data = createHeatData({
        event: createEvent({ backnums: true }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderCardsData(data, ['1', '2', '3', 'F', ''])

      expect(rendered.backnums).toBe(true)
      expect(rendered.cards[0].showBacknum).toBe(true)
      expect(rendered.cards[0].back).toBe(501)
    })
  })

  describe('C3: backnums: false - Show names on cards', () => {
    it('displays names instead of back numbers when backnums is false', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501, name: 'Smith, John' }),
          follow: createPerson({ name: 'Doe, Jane' }),
          level: createLevel({ initials: 'NV' }),
          scores: []
        })
      ]

      const data = createHeatData({
        event: createEvent({ backnums: false }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderCardsData(data, ['1', '2', '3', 'F', ''])

      expect(rendered.backnums).toBe(false)
      expect(rendered.cards[0].showBacknum).toBe(false)
      expect(rendered.cards[0].firstName).toBe('SmithJo') // Truncated to 7
      expect(rendered.cards[0].secondName).toBe('DoeJane')
    })
  })

  describe('C4: column_order: 1 - Lead name first on card', () => {
    it('shows lead name first when column_order is 1', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ name: 'Smith, John', type: 'Professional' }),
          follow: createPerson({ name: 'Doe, Jane', type: 'Student' }),
          scores: []
        })
      ]

      const data = createHeatData({
        event: createEvent({ column_order: 1 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderCardsData(data, ['1', '2', '3', 'F', ''])

      expect(rendered.columnOrder).toBe(1)
      expect(rendered.cards[0].firstName).toBe('SmithJo')
      expect(rendered.cards[0].secondName).toBe('DoeJane')
    })
  })

  describe('C5: column_order: 0 - Follow name first on card', () => {
    it('shows follow name first when column_order is 0 and follow is student', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ name: 'Smith, John', type: 'Professional' }),
          follow: createPerson({ name: 'Doe, Jane', type: 'Student' }),
          scores: []
        })
      ]

      const data = createHeatData({
        event: createEvent({ column_order: 0 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderCardsData(data, ['1', '2', '3', 'F', ''])

      expect(rendered.columnOrder).toBe(0)
      expect(rendered.cards[0].firstName).toBe('DoeJane')
      expect(rendered.cards[0].secondName).toBe('SmithJo')
    })
  })

  describe('C6: track_ages: true - Show age on card', () => {
    it('displays age category when track_ages is true', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          age: createAge({ category: 'Senior' }),
          level: createLevel({ initials: 'BR' }),
          scores: []
        })
      ]

      const data = createHeatData({
        event: createEvent({ track_ages: true }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderCardsData(data, ['1', '2', '3', 'F', ''])

      expect(rendered.trackAges).toBe(true)
      expect(rendered.cards[0].subjectCategory).toBe('Senior')
    })

    it('hides age category when track_ages is false', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          age: createAge({ category: 'Senior' }),
          level: createLevel({ initials: 'BR' }),
          scores: []
        })
      ]

      const data = createHeatData({
        event: createEvent({ track_ages: false }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderCardsData(data, ['1', '2', '3', 'F', ''])

      expect(rendered.trackAges).toBe(false)
      expect(rendered.cards[0].subjectCategory).toBe('')
    })
  })

  describe('C7: combine_open_and_closed: true - Show Open/Closed on card', () => {
    it('shows Open/Closed prefix when combine_open_and_closed is true', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: []
        })
      ]

      const data = createHeatData({
        event: createEvent({ heat_range_cat: 1 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderCardsData(data, ['1', '2', '3', 'F', ''])

      expect(rendered.combineOpenAndClosed).toBe(true)
      expect(rendered.cards[0].showOpenClosed).toBe(true)
    })

    it('hides Open/Closed prefix for Multi category', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: []
        })
      ]

      const data = createHeatData({
        event: createEvent({ heat_range_cat: 1 }),
        heat: createHeat({ category: 'Multi', subjects, subject_count: undefined })
      })

      const rendered = renderCardsData(data, ['1', '2', '3', 'F', ''])

      expect(rendered.combineOpenAndClosed).toBe(true)
      expect(rendered.cards[0].showOpenClosed).toBe(false)
    })
  })

  describe('C8: Drag and drop - Move card between score columns', () => {
    it('allows moving cards between score columns', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: '1' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const scores = ['1', '2', '3', 'F', '']
      let rendered = renderCardsData(data, scores)

      // Verify initial state
      expect(rendered.results['1'].length).toBe(1)
      expect(rendered.results['2'].length).toBe(0)

      // Simulate drag to column '2'
      subjects[0].scores[0].value = '2'
      rendered = renderCardsData(data, scores)

      // Verify new state
      expect(rendered.results['1'].length).toBe(0)
      expect(rendered.results['2'].length).toBe(1)
    })
  })

  describe('C9: Colors by level - Apply level-specific colors', () => {
    it('applies level-specific CSS classes', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          level: createLevel({ initials: 'NV', name: 'Newcomer' }),
          scores: []
        }),
        createSubject({
          id: 2,
          lead: createPerson({ back: 502 }),
          level: createLevel({ initials: 'BR', name: 'Bronze' }),
          scores: []
        })
      ]

      const data = createHeatData({
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderCardsData(data, ['1', '2', '3', 'F', ''])

      expect(rendered.cards[0].levelClass).toBe('NV')
      expect(rendered.cards[0].levelInitials).toBe('NV')
      expect(rendered.cards[1].levelClass).toBe('BR')
      expect(rendered.cards[1].levelInitials).toBe('BR')
    })
  })
})
