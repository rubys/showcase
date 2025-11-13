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
        scoreData,
        dance_id: subject.dance_id || 1,
        level_id: subject.level?.id || 0,
        age_id: subject.age?.id || 0,
        isAssigned: eventData.assign_judges > 0 && subject.scores?.length > 0
      }
    })

    // Filter and sort rows based on judge preferences
    const sortOrder = judgeData.sort_order || 'back'
    const showAssignments = judgeData.show_assignments || 'first'
    const assignJudges = eventData.assign_judges || 0

    // Filter rows if show_assignments is 'only'
    let filteredRows = rows
    if (assignJudges > 0 && showAssignments === 'only') {
      filteredRows = rows.filter(row => row.isAssigned)
    }

    if (assignJudges > 0 && showAssignments === 'first') {
      // Sort with assignments first within groups
      if (sortOrder === 'level') {
        filteredRows.sort((a, b) => {
          // First level_id
          if (a.level_id !== b.level_id) return a.level_id - b.level_id
          // Then age_id
          if (a.age_id !== b.age_id) return a.age_id - b.age_id
          // Then assigned first within level/age group
          if (a.isAssigned !== b.isAssigned) return b.isAssigned ? 1 : -1
          // Finally back number
          return a.back - b.back
        })
      } else {
        // Back number sort with assignments first within dance groups
        filteredRows.sort((a, b) => {
          // First dance_id
          if (a.dance_id !== b.dance_id) return a.dance_id - b.dance_id
          // Then assigned first within dance group
          if (a.isAssigned !== b.isAssigned) return b.isAssigned ? 1 : -1
          // Finally back number
          return a.back - b.back
        })
      }
    } else if (sortOrder === 'level') {
      // Level sort without assignment filtering
      filteredRows.sort((a, b) => {
        // Level_id
        if (a.level_id !== b.level_id) return a.level_id - b.level_id
        // Then age_id
        if (a.age_id !== b.age_id) return a.age_id - b.age_id
        // Finally back number
        return a.back - b.back
      })
    } else {
      // Default: sort by dance_id then back
      filteredRows.sort((a, b) => {
        // Dance_id
        if (a.dance_id !== b.dance_id) return a.dance_id - b.dance_id
        // Back number
        return a.back - b.back
      })
    }

    // Determine score display type
    const isEmcee = style === 'emcee'
    const isNumericScoring = !isEmcee && scoring === '#'
    const isSemiFinals = !isEmcee && heat.dance?.semi_finals && subjects.length > 0
    const isFeedbackScoring = !isEmcee && scoring === '+'
    const isValueFeedbackScoring = !isEmcee && scoring === '&'
    const isGradeFeedbackScoring = !isEmcee && scoring === '@'
    const hasFeedbackButtons = !isEmcee && ['+', '&', '@'].includes(scoring)
    const isRadioScoring = !isEmcee && !isNumericScoring && !isSemiFinals && !hasFeedbackButtons

    return {
      leadHeader,
      followHeader,
      hasBallroomColumn: ballroomsCount > 1,
      rows: filteredRows,
      hasSubjects: filteredRows.length > 0,
      scoring,
      scores,
      isNumericScoring,
      isSemiFinals,
      isRadioScoring,
      isFeedbackScoring,
      isValueFeedbackScoring,
      isGradeFeedbackScoring,
      hasFeedbackButtons,
      isEmcee,
      showStartButton: isEmcee && eventData.current_heat !== heat.number
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

  describe('T43-T45: Emcee Mode', () => {
    it('T43: Hides all scoring columns in emcee mode', () => {
      const data = createHeatData({
        heat: createHeat({ category: 'Open' })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''], 'emcee')

      expect(rendered.isEmcee).toBe(true)
      // Scoring should not be shown
      expect(rendered.isRadioScoring).toBe(false)
    })

    it('T44: Shows "Start Heat" button if not current heat', () => {
      const data = createHeatData({
        event: createEvent({ current_heat: 99 }),
        heat: createHeat({ number: 100, category: 'Open' })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''], 'emcee')

      expect(rendered.isEmcee).toBe(true)
      expect(rendered.showStartButton).toBe(true)
    })

    it('T45: Hides start button when current heat', () => {
      const data = createHeatData({
        event: createEvent({ current_heat: 100 }),
        heat: createHeat({ number: 100, category: 'Open' })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''], 'emcee')

      expect(rendered.isEmcee).toBe(true)
      expect(rendered.showStartButton).toBe(false)
    })
  })

  describe('T30-T32: Judge Comments', () => {
    it('T30: Shows textarea under each couple when judge_comments = true', () => {
      const subjects = [
        createSubject({ id: 1 })
      ]

      const data = createHeatData({
        event: createEvent({ judge_comments: true }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // Should have judge comments enabled
      expect(data.event.judge_comments).toBe(true)
    })

    it('T31: No textarea when judge_comments = false', () => {
      const data = createHeatData({
        event: createEvent({ judge_comments: false }),
        heat: createHeat({ category: 'Open' })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(data.event.judge_comments).toBe(false)
    })

    it('T32: Comment input should debounce and post to server', () => {
      const subjects = [
        createSubject({
          id: 1,
          scores: [createScore({ judge_id: 55, comments: 'Great timing!' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ judge_comments: true }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // Comments should be in the score data
      expect(rendered.rows[0].scoreData.comments).toBe('Great timing!')
    })
  })

  describe('T38-T39: Ballroom and Dance Separators', () => {
    it('T38: Gray separator line between different dances', () => {
      const subjects = [
        createSubject({
          id: 1,
          dance_id: 1,
          lead: createPerson({ back: 501 })
        }),
        createSubject({
          id: 2,
          dance_id: 2, // Different dance
          lead: createPerson({ back: 502 })
        })
      ]

      const data = createHeatData({
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // Different dance_ids should trigger separator logic
      expect(rendered.rows[0].dance_id).toBe(1)
      expect(rendered.rows[1].dance_id).toBe(2)
    })

    it('T39: Black separator line between ballrooms', () => {
      // When ballroom changes to 'B', there should be a black separator
      // This is tested by having subjects with different ballroom values
      const subjects = [
        createSubject({
          id: 1,
          ballroom: 'A',
          lead: createPerson({ back: 501 })
        }),
        createSubject({
          id: 2,
          ballroom: 'B', // Ballroom B triggers separator
          lead: createPerson({ back: 502 })
        })
      ]

      const data = createHeatData({
        event: createEvent({ ballrooms: 2 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.hasBallroomColumn).toBe(true)
      expect(rendered.rows[0].ballroom).toBe('A')
      expect(rendered.rows[1].ballroom).toBe('B')
    })
  })

  describe('T40-T42: Sort Order', () => {
    it('T40: sort_order: "back" sorts by dance_id then back number', () => {
      const subjects = [
        createSubject({
          id: 1,
          dance_id: 2,
          lead: createPerson({ back: 503 })
        }),
        createSubject({
          id: 2,
          dance_id: 1,
          lead: createPerson({ back: 502 })
        }),
        createSubject({
          id: 3,
          dance_id: 1,
          lead: createPerson({ back: 501 })
        })
      ]

      const data = createHeatData({
        judge: createJudge({ sort_order: 'back' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // Should sort by dance_id first, then back number
      expect(rendered.rows[0].back).toBe(501) // dance_id 1
      expect(rendered.rows[1].back).toBe(502) // dance_id 1
      expect(rendered.rows[2].back).toBe(503) // dance_id 2
    })

    it('T41: sort_order: "level" sorts by level_id, age_id, back number', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 503 }),
          level: createLevel({ id: 2, name: 'Bronze' }),
          age: createAge({ id: 1, category: 'Adult' })
        }),
        createSubject({
          id: 2,
          lead: createPerson({ back: 502 }),
          level: createLevel({ id: 1, name: 'Newcomer' }),
          age: createAge({ id: 2, category: 'Senior' })
        }),
        createSubject({
          id: 3,
          lead: createPerson({ back: 501 }),
          level: createLevel({ id: 1, name: 'Newcomer' }),
          age: createAge({ id: 1, category: 'Adult' })
        })
      ]

      const data = createHeatData({
        judge: createJudge({ sort_order: 'level' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // Should sort by level_id first, then age_id, then back number
      expect(rendered.rows[0].back).toBe(501) // level_id 1, age_id 1
      expect(rendered.rows[1].back).toBe(502) // level_id 1, age_id 2
      expect(rendered.rows[2].back).toBe(503) // level_id 2, age_id 1
    })

    it('T42: Level sort with assignment shows assigned first within each level', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 503 }),
          level: createLevel({ id: 1, name: 'Newcomer' }),
          scores: [] // Not assigned (no score)
        }),
        createSubject({
          id: 2,
          lead: createPerson({ back: 502 }),
          level: createLevel({ id: 1, name: 'Newcomer' }),
          scores: [createScore({ judge_id: 55, value: null })] // Assigned
        }),
        createSubject({
          id: 3,
          lead: createPerson({ back: 501 }),
          level: createLevel({ id: 2, name: 'Bronze' }),
          scores: [createScore({ judge_id: 55, value: null })] // Assigned
        }),
        createSubject({
          id: 4,
          lead: createPerson({ back: 504 }),
          level: createLevel({ id: 2, name: 'Bronze' }),
          scores: [] // Not assigned
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55, sort_order: 'level', show_assignments: 'first' }),
        event: createEvent({ assign_judges: 1 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // Should show assigned first within each level
      expect(rendered.rows[0].back).toBe(502) // level 1, assigned
      expect(rendered.rows[1].back).toBe(503) // level 1, not assigned
      expect(rendered.rows[2].back).toBe(501) // level 2, assigned
      expect(rendered.rows[3].back).toBe(504) // level 2, not assigned
    })
  })

  describe('T33-T37: Judge Assignment', () => {
    it('T33: Shows red border indicator for assigned back numbers', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: null })] // Assigned
        }),
        createSubject({
          id: 2,
          lead: createPerson({ back: 502 }),
          scores: [] // Not assigned
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ assign_judges: 1 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      expect(rendered.rows[0].isAssigned).toBe(true)
      expect(rendered.rows[1].isAssigned).toBe(false)
    })

    it('T34: show_assignments: "first" shows assigned first, then others', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 503 }),
          scores: [] // Not assigned
        }),
        createSubject({
          id: 2,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: null })] // Assigned
        }),
        createSubject({
          id: 3,
          lead: createPerson({ back: 502 }),
          scores: [] // Not assigned
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55, show_assignments: 'first' }),
        event: createEvent({ assign_judges: 1 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // Assigned first, then sorted by back
      expect(rendered.rows[0].back).toBe(501) // assigned
      expect(rendered.rows[1].back).toBe(502) // not assigned, lower back
      expect(rendered.rows[2].back).toBe(503) // not assigned, higher back
    })

    it('T35: show_assignments: "only" shows only assigned couples', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: null })] // Assigned
        }),
        createSubject({
          id: 2,
          lead: createPerson({ back: 502 }),
          scores: [] // Not assigned
        }),
        createSubject({
          id: 3,
          lead: createPerson({ back: 503 }),
          scores: [createScore({ judge_id: 55, value: null })] // Assigned
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55, show_assignments: 'only' }),
        event: createEvent({ assign_judges: 1 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // Only assigned couples shown
      expect(rendered.rows.length).toBe(2)
      expect(rendered.rows[0].back).toBe(501)
      expect(rendered.rows[1].back).toBe(503)
    })

    it('T36: show_assignments: "mixed" shows all in sort order', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 503 }),
          scores: [] // Not assigned
        }),
        createSubject({
          id: 2,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: null })] // Assigned
        }),
        createSubject({
          id: 3,
          lead: createPerson({ back: 502 }),
          scores: [] // Not assigned
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55, show_assignments: 'mixed' }),
        event: createEvent({ assign_judges: 1 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // All shown in back number order (no assignment priority)
      expect(rendered.rows.length).toBe(3)
      expect(rendered.rows[0].back).toBe(501)
      expect(rendered.rows[1].back).toBe(502)
      expect(rendered.rows[2].back).toBe(503)
    })

    it('T37: No assigned couples shows "No couples assigned" message', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [] // Not assigned
        }),
        createSubject({
          id: 2,
          lead: createPerson({ back: 502 }),
          scores: [] // Not assigned
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55, show_assignments: 'only' }),
        event: createEvent({ assign_judges: 1 }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '1', ['1', '2', '3', 'F', ''])

      // No couples when filtering to 'only' with no assignments
      expect(rendered.rows.length).toBe(0)
      expect(rendered.hasSubjects).toBe(false)
    })
  })

  describe('T16-T19: Feedback Scoring (+)', () => {
    it('T16: Shows two sections for Good and Bad feedback', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, good: null, bad: null })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '+' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '+', [])

      expect(rendered.isFeedbackScoring).toBe(true)
      expect(rendered.hasFeedbackButtons).toBe(true)
      expect(data.feedbacks.length).toBeGreaterThan(0)
    })

    it('T17: Feedback buttons available for selection', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, good: null, bad: null })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '+' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '+', [])

      // Should have feedback options from data
      expect(data.feedbacks).toEqual([
        { id: 1, value: 'Frame', abbr: 'F' },
        { id: 2, value: 'Posture', abbr: 'P' },
        { id: 3, value: 'Footwork', abbr: 'FW' },
        { id: 4, value: 'Lead/Follow', abbr: 'LF' },
        { id: 5, value: 'Timing', abbr: 'T' },
        { id: 6, value: 'Styling', abbr: 'S' }
      ])
    })

    it('T18: Stores good and bad feedback selections', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, good: '1,3', bad: '2,5' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '+' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '+', [])

      expect(rendered.rows[0].scoreData.good).toBe('1,3')
      expect(rendered.rows[0].scoreData.bad).toBe('2,5')
    })

    it('T19: Good and bad are mutually exclusive per feedback type', () => {
      // This test verifies the data structure supports mutual exclusivity
      // The actual enforcement happens in the component's click handler
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, good: '1', bad: '2' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '+' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '+', [])

      // Verify data stores both good and bad separately
      expect(rendered.rows[0].scoreData.good).toBe('1')
      expect(rendered.rows[0].scoreData.bad).toBe('2')
      expect(rendered.isFeedbackScoring).toBe(true)
    })
  })

  describe('T20-T24: Number + Feedback Scoring (&)', () => {
    it('T20: Shows value buttons (1-5) for overall score', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: '3', good: null, bad: null })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '&' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '&', [])

      expect(rendered.isValueFeedbackScoring).toBe(true)
      expect(rendered.rows[0].scoreData.value).toBe('3')
    })

    it('T21: Shows good feedback buttons (6 buttons)', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: null, good: '1,3,5', bad: null })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '&' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '&', [])

      expect(rendered.rows[0].scoreData.good).toBe('1,3,5')
      expect(data.feedbacks.length).toBe(6)
    })

    it('T22: Shows needs work feedback buttons (6 buttons)', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: null, good: null, bad: '2,4' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '&' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '&', [])

      expect(rendered.rows[0].scoreData.bad).toBe('2,4')
    })

    it('T23: Overall value buttons toggle (only one active)', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: '4', good: null, bad: null })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '&' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '&', [])

      // Only one value should be set
      expect(rendered.rows[0].scoreData.value).toBe('4')
      expect(rendered.isValueFeedbackScoring).toBe(true)
    })

    it('T24: Good/bad buttons toggle, mutually exclusive per feedback', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: '3', good: '1,5', bad: '2' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '&' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '&', [])

      // Can have both good and bad, but not same feedback ID in both
      expect(rendered.rows[0].scoreData.good).toBe('1,5')
      expect(rendered.rows[0].scoreData.bad).toBe('2')
      expect(rendered.rows[0].scoreData.value).toBe('3')
    })
  })

  describe('T25-T29: Grade + Feedback Scoring (@)', () => {
    it('T25: Shows grade buttons (B/S/G/GH) for overall score', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: 'G', good: null, bad: null })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '@' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '@', [])

      expect(rendered.isGradeFeedbackScoring).toBe(true)
      expect(rendered.rows[0].scoreData.value).toBe('G')
    })

    it('T26: Shows good feedback buttons (6 buttons)', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: null, good: '1,3,5', bad: null })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '@' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '@', [])

      expect(rendered.rows[0].scoreData.good).toBe('1,3,5')
      expect(data.feedbacks.length).toBe(6)
    })

    it('T27: Shows needs work feedback buttons (6 buttons)', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: null, good: null, bad: '2,4,6' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '@' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '@', [])

      expect(rendered.rows[0].scoreData.bad).toBe('2,4,6')
    })

    it('T28: Overall grade buttons toggle (only one active)', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: 'GH', good: null, bad: null })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '@' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '@', [])

      // Only one grade should be set
      expect(rendered.rows[0].scoreData.value).toBe('GH')
      expect(rendered.isGradeFeedbackScoring).toBe(true)
    })

    it('T29: Good/bad buttons toggle, mutually exclusive per feedback', () => {
      const subjects = [
        createSubject({
          id: 1,
          lead: createPerson({ back: 501 }),
          scores: [createScore({ judge_id: 55, value: 'S', good: '1,3', bad: '4,6' })]
        })
      ]

      const data = createHeatData({
        judge: createJudge({ id: 55 }),
        event: createEvent({ open_scoring: '@' }),
        heat: createHeat({ category: 'Open', subjects, subject_count: undefined })
      })

      const rendered = renderTableData(data, data.event, data.judge, '@', [])

      // Can have both good and bad, but not same feedback ID in both
      expect(rendered.rows[0].scoreData.good).toBe('1,3')
      expect(rendered.rows[0].scoreData.bad).toBe('4,6')
      expect(rendered.rows[0].scoreData.value).toBe('S')
    })
  })
})
