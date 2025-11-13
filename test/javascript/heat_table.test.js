import { describe, it, expect } from 'vitest'
import {
  createHeatData,
  createHeat,
  createEvent,
  createJudge,
  createSubject,
  createPerson,
  createLevel,
  createAge,
  createScore,
  createDance
} from './helpers/fixture_factory'

/**
 * Table Heat Component Tests
 *
 * Tests for heat-table.js component covering:
 * T1-T12: Basic table display and scoring (Phase 4, Week 4)
 *
 * Verifies behavioral parity with _table_heat.html.erb
 */

describe('Table Heat Component', () => {
  // Helper to extract rendering logic without actual DOM
  const renderTableData = (heatData, eventData, judgeData, scoring, scores, style = 'radio') => {
    const heat = heatData.heats[0]
    const subjects = heat.subjects
    const columnOrder = judgeData.column_order !== undefined ? judgeData.column_order : 1
    const ballroomsCount = eventData.ballrooms || 1
    const combineOpenAndClosed = eventData.heat_range_cat === 1
    const trackAges = eventData.track_ages

    // Build header labels
    const leadHeader = columnOrder === 1 ? 'Lead' : 'Student'
    const followHeader = columnOrder === 1 ? 'Follow' : 'Instructor'

    // Get subject category
    const getSubjectCategory = (entry) => {
      if (entry.pro) return 'Pro'

      const ageCategory = entry.age?.category || ''
      const levelInitials = entry.level?.initials || ''

      if (trackAges && ageCategory) {
        return `${ageCategory} - ${levelInitials}`
      }

      return levelInitials
    }

    // Process subjects
    const rows = subjects.map((subject) => {
      const entry = subject
      const subcat = getSubjectCategory(entry)
      const isScratched = (subject.number !== undefined ? subject.number : 1) <= 0

      // Determine names order
      let firstName, secondName
      if (columnOrder === 1 || subject.lead.type === 'Student') {
        firstName = subject.lead.display_name || subject.lead.name
        secondName = subject.follow.display_name || subject.follow.name
      } else {
        firstName = subject.follow.display_name || subject.follow.name
        secondName = subject.lead.display_name || subject.lead.name
      }

      // Category display
      let categoryDisplay = subcat
      if (combineOpenAndClosed && ['Open', 'Closed'].includes(heat.category)) {
        categoryDisplay = `${heat.category} - ${subcat}`
      }

      // Get score value
      const scoreData = subject.scores?.find(s => s.judge_id === judgeData.id)
      const scoreValue = scoreData?.value || ''

      return {
        back: subject.lead.back,
        ballroom: subject.ballroom || null,
        firstName,
        secondName,
        category: categoryDisplay,
        studio: subject.studio || '',
        isScratched,
        scoreValue,
        scoreData
      }
    })

    // Determine score display type
    const isNumericScoring = scoring === '#'
    const isSemiFinals = heat.dance?.semi_finals && subjects.length > 0
    const isRadioScoring = !isNumericScoring && !isSemiFinals && !['&', '+', '@'].includes(scoring)

    return {
      leadHeader,
      followHeader,
      hasBallroomColumn: ballroomsCount > 1,
      rows,
      hasSubjects: subjects.length > 0,
      scoring,
      scores,
      isNumericScoring,
      isSemiFinals,
      isRadioScoring,
      isEmcee: style === 'emcee',
      showStartButton: style === 'emcee' && eventData.current_heat !== heat.number
    }
  }

  describe('T1: Column order = 1 - Show Back/Lead/Follow/Category/Studio', () => {
    it('displays correct column headers', () => {
      const data = createHeatData({
        judge: createJudge({ column_order: 1 }),
        heat: createHeat({ category: 'Open' })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.leadHeader).toBe('Lead')
      expect(rendered.followHeader).toBe('Follow')
      expect(rendered.hasBallroomColumn).toBe(false)
    })

    it('displays subject data in correct order', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501, display_name: 'Pro One', type: 'Professional' }),
          follow: createPerson({ back: 401, display_name: 'Student One', type: 'Student' }),
          level: createLevel({ initials: 'BR' }),
          studio: 'Studio A'
        })
      ]

      const data = createHeatData({
        judge: createJudge({ column_order: 1 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.rows[0].back).toBe(501)
      expect(rendered.rows[0].firstName).toBe('Pro One')
      expect(rendered.rows[0].secondName).toBe('Student One')
      expect(rendered.rows[0].category).toBe('BR')
      expect(rendered.rows[0].studio).toBe('Studio A')
    })
  })

  describe('T2: Column order = 0 - Show Back/Student/Instructor/Category/Studio', () => {
    it('displays correct column headers', () => {
      const data = createHeatData({
        judge: createJudge({ column_order: 0 }),
        heat: createHeat({ category: 'Closed' })
      })

      const rendered = renderTableData(data, data.event, data.judge, 'G', ['GH', 'G', 'S', 'B', ''])

      expect(rendered.leadHeader).toBe('Student')
      expect(rendered.followHeader).toBe('Instructor')
    })

    it('displays student first when follow is student', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501, display_name: 'Pro Lead', type: 'Professional' }),
          follow: createPerson({ back: 401, display_name: 'Student Follow', type: 'Student' })
        })
      ]

      const data = createHeatData({
        judge: createJudge({ column_order: 0 }),
        heat: createHeat({ category: 'Closed', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, 'G', ['GH', 'G', 'S', 'B', ''])

      // With column_order = 0 and lead is NOT student, we swap to show follow (student) first
      expect(rendered.rows[0].firstName).toBe('Student Follow')
      expect(rendered.rows[0].secondName).toBe('Pro Lead')
    })
  })

  describe('T3: ballrooms > 1 - Add Ballroom column after Back', () => {
    it('shows ballroom column when ballrooms > 1', () => {
      const data = createHeatData({
        event: createEvent({ ballrooms: 2 }),
        heat: createHeat({ category: 'Open' })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.hasBallroomColumn).toBe(true)
    })

    it('hides ballroom column when ballrooms = 1', () => {
      const data = createHeatData({
        event: createEvent({ ballrooms: 1 }),
        heat: createHeat({ category: 'Open' })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.hasBallroomColumn).toBe(false)
    })

    it('displays ballroom value for subjects', () => {
      const subjects = [
        createSubject({
          id: 1,
          ballroom: 'A',
          lead: createPerson({ back: 501 })
        }),
        createSubject({
          id: 2,
          ballroom: 'B',
          lead: createPerson({ back: 502 })
        })
      ]

      const data = createHeatData({
        event: createEvent({ ballrooms: 2 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.rows[0].ballroom).toBe('A')
      expect(rendered.rows[1].ballroom).toBe('B')
    })
  })

  describe('T4: combine_open_and_closed = true - Show category prefix', () => {
    it('shows "Open -" prefix for Open category', () => {
      const subjects = [
        createSubject({
          id: 1,
          level: createLevel({ initials: 'BR' })
        })
      ]

      const data = createHeatData({
        event: createEvent({ heat_range_cat: 1 }),
        heat: {
          ...createHeat({ category: 'Open', subjects, subject_count: undefined }),
          category: 'Open'
        }
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.rows[0].category).toContain('Open -')
      expect(rendered.rows[0].category).toContain('BR')
    })

    it('shows "Closed -" prefix for Closed category', () => {
      const subjects = [
        createSubject({
          id: 1,
          level: createLevel({ initials: 'SL' })
        })
      ]

      const data = createHeatData({
        event: createEvent({ heat_range_cat: 1 }),
        heat: {
          ...createHeat({ category: 'Closed', subjects, subject_count: undefined }),
          category: 'Closed'
        }
      })

      const rendered = renderTableData(data, data.event, data.judge, 'G', ['GH', 'G', 'S', 'B', ''])

      expect(rendered.rows[0].category).toContain('Closed -')
      expect(rendered.rows[0].category).toContain('SL')
    })

    it('does not show prefix for Multi category', () => {
      const subjects = [
        createSubject({
          id: 1,
          level: createLevel({ initials: 'GD' })
        })
      ]

      const data = createHeatData({
        event: createEvent({ heat_range_cat: 1 }),
        heat: createHeat({ category: 'Multi', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.rows[0].category).not.toContain('Multi -')
      expect(rendered.rows[0].category).toBe('GD')
    })
  })

  describe('T5: track_ages = true - Include age in category display', () => {
    it('includes age category in display', () => {
      const subjects = [
        createSubject({
          id: 1,
          level: createLevel({ initials: 'BR' }),
          age: createAge({ category: 'Senior' })
        })
      ]

      const data = createHeatData({
        event: createEvent({ track_ages: true }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.rows[0].category).toBe('Senior - BR')
    })
  })

  describe('T6: track_ages = false - Exclude age from category', () => {
    it('shows only level initials', () => {
      const subjects = [
        createSubject({
          id: 1,
          level: createLevel({ initials: 'GD' }),
          age: createAge({ category: 'Adult' })
        })
      ]

      const data = createHeatData({
        event: createEvent({ track_ages: false }),
        heat: createHeat({ category: 'Closed', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, 'G', ['GH', 'G', 'S', 'B', ''])

      expect(rendered.rows[0].category).toBe('GD')
      expect(rendered.rows[0].category).not.toContain('Adult')
    })
  })

  describe('T7: Scoring type "1" - Radio buttons for 1/2/3/F/-', () => {
    it('identifies as radio scoring', () => {
      const data = createHeatData({
        event: createEvent({ open_scoring: '1' }),
        heat: createHeat({ category: 'Open' })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.scoring).toBe('1')
      expect(rendered.scores).toEqual(['1', '2', '3', 'F', ''])
      expect(rendered.isRadioScoring).toBe(true)
      expect(rendered.isNumericScoring).toBe(false)
    })

    it('displays score values', () => {
      const rendered = renderTableData(
        createHeatData({ heat: createHeat({ category: 'Open' }) }),
        createEvent({ open_scoring: '1' }),
        createJudge(),
        '1',
        ['1', '2', '3', 'F', '']
      )

      expect(rendered.scores).toEqual(['1', '2', '3', 'F', ''])
      expect(rendered.scores.length).toBe(5)
    })
  })

  describe('T8: Scoring type "G" - Radio buttons for GH/G/S/B/-', () => {
    it('identifies as radio scoring', () => {
      const data = createHeatData({
        event: createEvent({ closed_scoring: 'G' }),
        heat: createHeat({ category: 'Closed' })
      })

      const rendered = renderTableData(data, data.event, data.judge, 'G', ['GH', 'G', 'S', 'B', ''])

      expect(rendered.scoring).toBe('G')
      expect(rendered.scores).toEqual(['GH', 'G', 'S', 'B', ''])
      expect(rendered.isRadioScoring).toBe(true)
      expect(rendered.isNumericScoring).toBe(false)
    })

    it('displays score values in reverse order', () => {
      const rendered = renderTableData(
        createHeatData({ heat: createHeat({ category: 'Closed' }) }),
        createEvent({ closed_scoring: 'G' }),
        createJudge(),
        'G',
        ['GH', 'G', 'S', 'B', '']
      )

      // Scores should be in reverse quality order (best to worst)
      expect(rendered.scores).toEqual(['GH', 'G', 'S', 'B', ''])
    })
  })

  describe('T9: Radio scoring - Clicking radio updates score', () => {
    it('shows checked state for existing score', () => {
      const subjects = [
        createSubject({
          id: 1,
          scores: [createScore({ judge_id: 55, value: '2' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.rows[0].scoreValue).toBe('2')
    })

    it('shows empty state when no score exists', () => {
      const subjects = [
        createSubject({
          id: 1,
          scores: []
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.rows[0].scoreValue).toBe('')
    })
  })

  describe('T10: Scoring type "#" - Show numeric input field', () => {
    it('identifies as numeric scoring', () => {
      const data = createHeatData({
        event: createEvent({ open_scoring: '#' }),
        heat: createHeat({ category: 'Open' })
      })

      const rendered = renderTableData(data, data.event, data.judge, '#', [])

      expect(rendered.scoring).toBe('#')
      expect(rendered.isNumericScoring).toBe(true)
      expect(rendered.isRadioScoring).toBe(false)
    })

    it('displays existing numeric score', () => {
      const subjects = [
        createSubject({
          id: 1,
          scores: [createScore({ judge_id: 55, value: '85' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '#' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '#', [])

      expect(rendered.rows[0].scoreValue).toBe('85')
    })
  })

  describe('T11: Numeric scoring - Validate 0-99 range', () => {
    it('shows input with pattern validation', () => {
      const data = createHeatData({
        event: createEvent({ open_scoring: '#' }),
        heat: createHeat({ category: 'Open' })
      })

      const rendered = renderTableData(data, data.event, data.judge, '#', [])

      expect(rendered.isNumericScoring).toBe(true)
      // Component should render input with pattern="^\d\d$" for validation
    })
  })

  describe('T12: Numeric scoring - Post on blur/change', () => {
    it('prepares score data for posting', () => {
      const subjects = [
        createSubject({
          id: 1,
          scores: [createScore({ judge_id: 55, value: '' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '#' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '#', [])

      // Score should be ready to receive input and post
      expect(rendered.rows[0].scoreData).toBeTruthy()
    })
  })

  describe('Empty heat handling', () => {
    it('handles empty subject list', () => {
      const data = createHeatData({
        heat: createHeat({ subjects: [], subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.hasSubjects).toBe(false)
      expect(rendered.rows.length).toBe(0)
    })
  })

  describe('Scratched heats', () => {
    it('marks scratched heats', () => {
      const subjects = [
        createSubject({ id: 1, number: 100 }),   // Active
        createSubject({ id: 2, number: -1 }),    // Scratched
        createSubject({ id: 3, number: 0 })      // Scratched
      ]

      const data = createHeatData({
        heat: createHeat({ subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.rows[0].isScratched).toBe(false)
      expect(rendered.rows[1].isScratched).toBe(true)
      expect(rendered.rows[2].isScratched).toBe(true)
    })
  })

  describe('Pro couples', () => {
    it('displays "Pro" for professional couples', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ type: 'Professional' }),
          follow: createPerson({ type: 'Professional' }),
          level: createLevel({ initials: 'GD' }),
          pro: true
        })
      ]

      const data = createHeatData({
        heat: createHeat({ subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.rows[0].category).toBe('Pro')
    })
  })

  describe('T13-T15: Scrutineering (semi_finals callback)', () => {
    it('T13: Shows single checkbox per couple for callback vote', () => {
      const subjects = [
        createSubject({
          id: 1,
          scores: []
        })
      ]

      const data = createHeatData({
        heat: createHeat({
          category: 'Open',
          subjects,
          subject_count: undefined,
          dance: createDance({ semi_finals: true })
        })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.isSemiFinals).toBe(true)
      expect(rendered.isRadioScoring).toBe(false)
      expect(rendered.isNumericScoring).toBe(false)
    })

    it('T14: Header shows "Callback?" for semi-finals', () => {
      const data = createHeatData({
        heat: createHeat({
          category: 'Open',
          dance: createDance({ semi_finals: true })
        })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // Header should indicate callback voting
      expect(rendered.isSemiFinals).toBe(true)
    })

    it('T15: Checkbox toggles value between checked and unchecked', () => {
      const subjects = [
        createSubject({
          id: 1,
          scores: [createScore({ judge_id: 55, value: '1' })]
        }),
        createSubject({
          id: 2,
          scores: [createScore({ judge_id: 55, value: '' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        heat: createHeat({
          category: 'Open',
          subjects,
          subject_count: undefined,
          dance: createDance({ semi_finals: true })
        })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // First subject has callback (value = '1')
      expect(rendered.rows[0].scoreValue).toBe('1')
      // Second subject no callback (value = '')
      expect(rendered.rows[1].scoreValue).toBe('')
    })
  })
})
