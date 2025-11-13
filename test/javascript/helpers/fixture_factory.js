/**
 * Test Fixture Factory
 *
 * Creates test data for heat components with configurable options.
 * Generates realistic data structures matching the JSON API format.
 */

/**
 * Create event configuration
 */
export const createEvent = (overrides = {}) => {
  return {
    id: 1,
    name: 'Test Showcase 2025',
    open_scoring: overrides.open_scoring || '1',
    closed_scoring: overrides.closed_scoring || 'G',
    multi_scoring: overrides.multi_scoring || '1',
    solo_scoring: overrides.solo_scoring || '1',
    heat_range_cat: overrides.heat_range_cat !== undefined ? overrides.heat_range_cat : 0,
    assign_judges: overrides.assign_judges !== undefined ? overrides.assign_judges : 0,
    backnums: overrides.backnums !== undefined ? overrides.backnums : true,
    track_ages: overrides.track_ages !== undefined ? overrides.track_ages : false,
    ballrooms: overrides.ballrooms || 1,
    column_order: overrides.column_order !== undefined ? overrides.column_order : 1,
    judge_comments: overrides.judge_comments !== undefined ? overrides.judge_comments : false,
    ...overrides
  }
}

/**
 * Create judge configuration
 */
export const createJudge = (overrides = {}) => {
  return {
    id: overrides.id || 55,
    name: overrides.name || 'Judge Smith',
    display_name: overrides.display_name || 'Judge Smith',
    sort_order: overrides.sort_order || 'back',
    show_assignments: overrides.show_assignments || 'first',
    review_solos: overrides.review_solos || 'all',
    ...overrides
  }
}

/**
 * Create person (student/professional)
 */
export const createPerson = (overrides = {}) => {
  return {
    id: overrides.id || 1,
    name: overrides.name || 'Test Person',
    display_name: overrides.display_name || 'Test Person',
    back: overrides.back || null,
    type: overrides.type || 'Student',
    studio: overrides.studio || createStudio(),
    ...overrides
  }
}

/**
 * Create studio
 */
export const createStudio = (overrides = {}) => {
  return {
    id: overrides.id || 1,
    name: overrides.name || 'Test Studio',
    ...overrides
  }
}

/**
 * Create age category
 */
export const createAge = (overrides = {}) => {
  return {
    id: overrides.id || 1,
    category: overrides.category || 'Adult',
    ...overrides
  }
}

/**
 * Create level
 */
export const createLevel = (overrides = {}) => {
  return {
    id: overrides.id || 1,
    name: overrides.name || 'Newcomer',
    initials: overrides.initials || 'NV',
    ...overrides
  }
}

/**
 * Create entry (lead/follow pair)
 */
export const createEntry = (overrides = {}) => {
  const leadType = overrides.leadType || 'Professional'
  const followType = overrides.followType || 'Student'

  return {
    id: overrides.id || 1,
    lead: overrides.lead || createPerson({ id: 101, name: 'Pro Leader', type: leadType, back: 501 }),
    follow: overrides.follow || createPerson({ id: 201, name: 'Student Follower', type: followType, back: 401 }),
    instructor: overrides.instructor || null,
    studio: overrides.studio || 'Test Studio',
    age: overrides.age || null,
    level: overrides.level || createLevel(),
    ...overrides
  }
}

/**
 * Create dance
 */
export const createDance = (overrides = {}) => {
  return {
    id: overrides.id || 1,
    name: overrides.name || 'Waltz',
    heat_length: overrides.heat_length !== undefined ? overrides.heat_length : 0,
    uses_scrutineering: overrides.uses_scrutineering !== undefined ? overrides.uses_scrutineering : false,
    multi_children: overrides.multi_children || [],
    multi_parent: overrides.multi_parent || null,
    category_name: overrides.category_name || 'Smooth',
    ballrooms: overrides.ballrooms || 1,
    songs: overrides.songs || [],
    ...overrides
  }
}

/**
 * Create formation (for solo heats)
 */
export const createFormation = (overrides = {}) => {
  return {
    id: overrides.id || 1,
    person_id: overrides.person_id || 301,
    person_name: overrides.person_name || 'Formation Member',
    on_floor: overrides.on_floor !== undefined ? overrides.on_floor : true,
    ...overrides
  }
}

/**
 * Create solo
 */
export const createSolo = (overrides = {}) => {
  return {
    id: overrides.id || 1,
    order: overrides.order || 1,
    formations: overrides.formations || [],
    combo_dance_id: overrides.combo_dance_id || null,
    combo_dance: overrides.combo_dance || null,
    song: overrides.song || '',
    artist: overrides.artist || '',
    ...overrides
  }
}

/**
 * Create score
 */
export const createScore = (overrides = {}) => {
  return {
    id: overrides.id || 1,
    judge_id: overrides.judge_id || 55,
    heat_id: overrides.heat_id || 1,
    slot: overrides.slot || null,
    good: overrides.good || null,
    bad: overrides.bad || null,
    value: overrides.value || null,
    comments: overrides.comments || null,
    ...overrides
  }
}

/**
 * Create subject (heat entry with scores)
 */
export const createSubject = (overrides = {}) => {
  // Allow explicit override of entry sub-properties
  let entry
  if (overrides.lead || overrides.follow || overrides.level || overrides.instructor || overrides.age) {
    entry = createEntry({
      lead: overrides.lead,
      follow: overrides.follow,
      instructor: overrides.instructor,
      studio: overrides.studio,
      age: overrides.age,
      level: overrides.level
    })
  } else {
    entry = overrides.entry || createEntry()
  }

  return {
    id: overrides.id || 1,
    dance_id: overrides.dance_id || 1,
    entry_id: overrides.entry_id || 1,
    lead: overrides.lead || entry.lead,
    follow: overrides.follow || entry.follow,
    instructor: overrides.instructor || entry.instructor,
    studio: overrides.studio || entry.studio,
    age: overrides.age || entry.age,
    level: overrides.level || entry.level,
    solo: overrides.solo !== undefined ? overrides.solo : null,
    scores: overrides.scores || [],
    ...overrides
  }
}

/**
 * Create complete heat data
 */
export const createHeat = (overrides = {}) => {
  const category = overrides.category || 'Closed'
  const dance = overrides.dance || createDance({ name: 'Waltz' })

  // Create default subjects if not provided
  let subjects = overrides.subjects
  if (!subjects) {
    const subjectCount = overrides.subject_count || 1
    subjects = Array.from({ length: subjectCount }, (_, i) =>
      createSubject({
        id: i + 1,
        entry_id: i + 1,
        entry: createEntry({
          id: i + 1,
          lead: createPerson({ id: 100 + i, name: `Pro ${i + 1}`, type: 'Professional', back: 500 + i }),
          follow: createPerson({ id: 200 + i, name: `Student ${i + 1}`, type: 'Student', back: 400 + i })
        })
      })
    )
  }

  return {
    number: overrides.number || 100,
    category: category,
    scoring: overrides.scoring || '1',
    dance: dance,
    subjects: subjects,
    ...overrides
  }
}

/**
 * Create complete data structure (full API response)
 */
export const createHeatData = (overrides = {}) => {
  const event = createEvent(overrides.event || {})
  const judge = createJudge(overrides.judge || {})

  // Create heats if not provided
  let heats = overrides.heats
  if (!heats) {
    heats = [createHeat(overrides.heat || {})]
  }

  return {
    event,
    judge,
    heats,
    feedbacks: overrides.feedbacks || [
      { id: 1, value: 'Frame', abbr: 'F' },
      { id: 2, value: 'Posture', abbr: 'P' },
      { id: 3, value: 'Footwork', abbr: 'FW' },
      { id: 4, value: 'Lead/Follow', abbr: 'LF' },
      { id: 5, value: 'Timing', abbr: 'T' },
      { id: 6, value: 'Styling', abbr: 'S' }
    ],
    score_options: overrides.score_options || {
      "Open": ['1', '2', '3', 'F', ''],
      "Closed": ['GH', 'G', 'S', 'B', ''],
      "Solo": ['1', '2', '3', 'F', ''],
      "Multi": ['1', '2', '3', 'F', '']
    },
    timestamp: overrides.timestamp || Date.now()
  }
}

/**
 * Helper: Create heat with multiple subjects for testing sorting/filtering
 */
export const createHeatWithMultipleSubjects = (config = {}) => {
  const subjects = []
  const count = config.count || 5

  for (let i = 0; i < count; i++) {
    subjects.push(createSubject({
      id: i + 1,
      entry: createEntry({
        id: i + 1,
        lead: createPerson({
          id: 100 + i,
          name: `Pro ${i + 1}`,
          type: 'Professional',
          back: 500 + i
        }),
        follow: createPerson({
          id: 200 + i,
          name: `Student ${i + 1}`,
          type: 'Student',
          back: 400 + i
        }),
        level: createLevel({
          id: (i % 3) + 1,
          name: ['Newcomer', 'Bronze', 'Silver'][i % 3],
          initials: ['NV', 'BR', 'SL'][i % 3]
        }),
        age: config.track_ages ? createAge({ id: (i % 2) + 1, category: ['Adult', 'Senior'][i % 2] }) : null
      }),
      scores: config.with_scores ? [createScore({ judge_id: 55, heat_id: i + 1, value: null })] : []
    }))
  }

  return createHeat({
    ...config,
    subjects,
    subject_count: undefined // Remove this since we created subjects manually
  })
}

/**
 * Helper: Create solo heat with formations
 */
export const createSoloHeat = (config = {}) => {
  // Only use default formations if not explicitly provided and no subjects provided
  let formations = config.formations
  if (!formations && !config.subjects) {
    formations = []  // Default to empty formations unless explicitly provided
  }

  // If subjects are provided, use them directly
  if (config.subjects) {
    return createHeat({
      ...config,
      category: 'Solo'
    })
  }

  // Otherwise create default subject
  return createHeat({
    ...config,
    category: 'Solo',
    subjects: [
      createSubject({
        id: 1,
        lead: createPerson({ id: 101, name: 'Lead Dancer', type: 'Student' }),
        follow: createPerson({ id: 102, name: 'Follow Dancer', type: 'Professional' }),
        solo: createSolo({
          formations: formations || [],
          song: config.song || 'Test Song',
          artist: config.artist || 'Test Artist',
          combo_dance_id: config.combo_dance_id || null,
          combo_dance: config.combo_dance || null
        })
      })
    ]
  })
}

/**
 * Helper: Create multi-dance heat with scrutineering
 */
export const createMultiHeat = (config = {}) => {
  const childCount = config.child_count || 2
  const children = Array.from({ length: childCount }, (_, i) => ({
    id: i + 1,
    name: config.child_names ? config.child_names[i] : `Dance ${i + 1}`
  }))

  return createHeat({
    ...config,
    category: 'Multi',
    dance: createDance({
      id: 1,
      name: config.dance_name || 'Latin 2 Dance',
      heat_length: config.heat_length || 2,
      uses_scrutineering: config.uses_scrutineering !== undefined ? config.uses_scrutineering : true,
      multi_children: children
    })
  })
}
