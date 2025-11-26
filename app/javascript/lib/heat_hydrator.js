// Shared heat data hydration logic
// Used by both the browser (heat_app_controller.js) and Node.js scripts
//
// ARCHITECTURAL PRINCIPLE: Server computes, hydration joins, template filters
//
// - Server (ScoresController#heats_data): Computes all derived/display values (e.g., dance_string = "Closed Milonga")
//   and serializes them in the JSON response. Performs business logic, aggregations, and formatting.
//
// - Hydration (this file): Joins normalized data by resolving IDs to full objects.
//   Converts { dance_id: 5 } to { dance: { id: 5, name: "Milonga" } }.
//   Does NOT compute business logic or derived values.
//
// - Templates (ERB/JS): Filter and format data for display (e.g., truncate, titleize, pluralize).
//   Present data that has already been computed and joined.
//
// This separation ensures consistent behavior between ERB and JS views, with a single source of truth
// for business logic (the server) and clear responsibilities for each layer.

/**
 * Build lookup tables from raw normalized data
 */
export function buildLookupTables(rawData) {
  const lookups = {
    people: rawData.people || {},
    studios: rawData.studios || {},
    entries: rawData.entries || {},
    dances: rawData.dances || {},
    ages: rawData.ages || {},
    levels: rawData.levels || {},
    solos: rawData.solos || {},
    formations: rawData.formations || {},
    scores: rawData.scores || {},
    heatsByNumber: {}
  }

  // Build heats by number for easy lookup
  if (rawData.heats) {
    rawData.heats.forEach(heat => {
      if (!lookups.heatsByNumber[heat.number]) {
        lookups.heatsByNumber[heat.number] = []
      }
      lookups.heatsByNumber[heat.number].push(heat)
    })
  }

  return lookups
}

/**
 * Hydrate a single heat - convert IDs to full objects
 */
export function hydrateHeat(heat, lookups) {
  const hydrated = { ...heat }

  // Hydrate dance
  if (heat.dance_id && lookups.dances[heat.dance_id]) {
    hydrated.dance = lookups.dances[heat.dance_id]
  }

  // Hydrate entry
  if (heat.entry_id) {
    // Use entry from lookup table if available, otherwise use embedded entry from heat
    const entryData = lookups.entries[heat.entry_id] || heat.entry
    if (entryData) {
      const entry = { ...entryData }

      // Hydrate lead
      if (entry.lead_id && lookups.people[entry.lead_id]) {
        const lead = { ...lookups.people[entry.lead_id] }
        if (lead.studio_id && lookups.studios[lead.studio_id]) {
          lead.studio = lookups.studios[lead.studio_id]
        }
        entry.lead = lead
      }

      // Hydrate follow
      if (entry.follow_id && lookups.people[entry.follow_id]) {
        const follow = { ...lookups.people[entry.follow_id] }
        if (follow.studio_id && lookups.studios[follow.studio_id]) {
          follow.studio = lookups.studios[follow.studio_id]
        }
        entry.follow = follow
      }

      // Hydrate instructor
      if (entry.instructor_id && lookups.people[entry.instructor_id]) {
        const instructor = { ...lookups.people[entry.instructor_id] }
        if (instructor.studio_id && lookups.studios[instructor.studio_id]) {
          instructor.studio = lookups.studios[instructor.studio_id]
        }
        entry.instructor = instructor
      }

      // Hydrate age and level
      if (entry.age_id && lookups.ages[entry.age_id]) {
        entry.age = lookups.ages[entry.age_id]
      }
      if (entry.level_id && lookups.levels[entry.level_id]) {
        entry.level = lookups.levels[entry.level_id]
      }

      hydrated.entry = entry

      // Add lead/follow/subject at top level for template compatibility
      if (entry.lead) {
        hydrated.lead = entry.lead
      }
      if (entry.follow) {
        hydrated.follow = entry.follow
      }
      // Subject is the student in student/professional pairings
      if (entry.lead && entry.lead.type === 'Student') {
        hydrated.subject = entry.lead
      } else if (entry.follow && entry.follow.type === 'Student') {
        hydrated.subject = entry.follow
      }
    }
  }

  // Hydrate solo
  if (heat.solo_id) {
    // Use solo from lookup table if available, otherwise use embedded solo from heat
    const soloData = lookups.solos[heat.solo_id] || heat.solo
    if (soloData) {
      hydrated.solo = { ...soloData }

      // Hydrate combo_dance if present
      if (hydrated.solo.combo_dance_id && lookups.dances[hydrated.solo.combo_dance_id]) {
        hydrated.solo.combo_dance = lookups.dances[hydrated.solo.combo_dance_id]
      }

      // Hydrate formations - use embedded formations if available, otherwise lookup
      if (hydrated.solo.formations) {
        // Formations already embedded (from per-heat endpoint), just hydrate person refs
        hydrated.solo.formations = hydrated.solo.formations.map(formation => {
          const f = { ...formation }
          if (f.person_id && lookups.people[f.person_id]) {
            const person = { ...lookups.people[f.person_id] }
            if (person.studio_id && lookups.studios[person.studio_id]) {
              person.studio = lookups.studios[person.studio_id]
            }
            f.person = person
          }
          return f
        })
      } else {
        // Lookup formations from global table (from bulk endpoint)
        hydrated.solo.formations = Object.values(lookups.formations)
          .filter(f => f.solo_id === heat.solo_id)
          .map(formation => {
            const f = { ...formation }
            if (f.person_id && lookups.people[f.person_id]) {
              const person = { ...lookups.people[f.person_id] }
              if (person.studio_id && lookups.studios[person.studio_id]) {
                person.studio = lookups.studios[person.studio_id]
              }
              f.person = person
            }
            return f
          })
      }
    }
  }

  // Hydrate scores
  hydrated.scores = Object.values(lookups.scores)
    .filter(s => s.heat_id === heat.id)

  return hydrated
}

/**
 * Build complete template data for a heat
 * This matches the exact logic from heat_app_controller.js showHeat method
 * Used by both browser and Node.js scripts to ensure identical rendering
 */
export function buildHeatTemplateData(heatNumber, rawData, style) {
  const lookups = buildLookupTables(rawData)
  const event = rawData.event
  const judge = rawData.judge

  // Find all heats with this number
  const heatsWithNumber = lookups.heatsByNumber[heatNumber] ||
                          lookups.heatsByNumber[parseFloat(heatNumber)] ||
                          lookups.heatsByNumber[String(heatNumber)]

  if (!heatsWithNumber || heatsWithNumber.length === 0) {
    throw new Error(`Heat ${heatNumber} not found`)
  }

  // Hydrate all heats with this number (basic hydration only)
  let hydratedHeats = heatsWithNumber.map(h => hydrateHeat(h, lookups))

  // Get primary heat for main properties
  const primaryHeat = hydratedHeats[0]
  const dance = primaryHeat.dance
  const category = primaryHeat.category

  // === CATEGORY SCORING LOGIC ===
  // Use server-computed category_id (avoids duplicating business logic)
  const categoryId = primaryHeat.category_scoring_category_id

  // Check if category scoring is enabled (server provides this)
  const categoryRecord = categoryId && rawData.categories ? rawData.categories[categoryId] : null
  const categoryScoringEnabled = event.student_judge_assignments && categoryRecord?.use_category_scoring

  // Apply category scoring expansion if enabled
  if (categoryScoringEnabled) {
    const expandedSubjects = []

    // Build lookup for category scores: heat_id = -category_id, keyed by person_id
    const categoryScores = {}
    if (categoryId) {
      Object.values(lookups.scores).forEach(score => {
        if (score.heat_id === -categoryId && score.judge_id === judge.id && score.person_id) {
          categoryScores[score.person_id] = [score]
        }
      })
    }

    hydratedHeats.forEach(subject => {
      if (!subject) {
        return
      }

      const students = []

      // Identify students in this couple
      if (subject.lead && subject.lead.type === 'Student') {
        students.push({ student: subject.lead, role: 'lead' })
      }
      if (subject.follow && subject.follow.type === 'Student') {
        students.push({ student: subject.follow, role: 'follow' })
      }

      if (students.length === 2) {
        // Amateur couple - create two entries, one for each student
        students.forEach(studentInfo => {
          const studentScores = categoryScores[studentInfo.student.id] || []

          expandedSubjects.push({
            ...subject,
            subject: studentInfo.student,       // The student being scored
            student_role: studentInfo.role,     // 'lead' or 'follow'
            scores: studentScores               // Category score for this student
          })
        })
      } else if (students.length === 1) {
        // Single student - keep as-is but mark the student
        const studentScores = categoryScores[students[0].student.id] || []

        expandedSubjects.push({
          ...subject,
          subject: students[0].student,
          student_role: students[0].role,
          scores: studentScores
        })
      } else {
        // Pro/Am - no students, keep as-is
        expandedSubjects.push(subject)
      }
    })

    hydratedHeats = expandedSubjects
  }

  // Build category score assignments (student IDs that have category scores in THIS heat)
  const allCategoryAssignments = categoryId && rawData.category_score_assignments && rawData.category_score_assignments[categoryId]
    ? new Set(rawData.category_score_assignments[categoryId])
    : new Set()

  const categoryScoreAssignments = []
  hydratedHeats.forEach(subject => {
    const studentId = subject.subject?.id
    if (studentId && allCategoryAssignments.has(studentId)) {
      if (!categoryScoreAssignments.includes(studentId)) {
        categoryScoreAssignments.push(studentId)
      }
    }
  })

  // === END CATEGORY SCORING LOGIC ===

  // Use server-computed scoring type (avoids duplicating business logic)
  const scoring = primaryHeat.scoring_type

  // Group subjects by ballroom (matches logic from heat controller action)
  const ballrooms = {}
  let ballroomsCount = 0
  hydratedHeats.forEach(heat => {
    const ballroom = heat.ballroom || 1
    if (!ballrooms[ballroom]) {
      ballrooms[ballroom] = []
      ballroomsCount++
    }
    ballrooms[ballroom].push(heat)
  })

  // Determine final and callbacks flags
  const final = dance.uses_scrutineering && scoring.startsWith('rank')
  const callbacks = dance.uses_scrutineering && scoring === 'check'

  // Calculate prev/next heat numbers
  const allHeatNumbers = Object.keys(lookups.heatsByNumber).map(n => parseFloat(n)).sort((a, b) => a - b)
  const currentIndex = allHeatNumbers.indexOf(parseFloat(heatNumber))
  const prev = currentIndex > 0 ? allHeatNumbers[currentIndex - 1] : null
  const next = currentIndex < allHeatNumbers.length - 1 ? allHeatNumbers[currentIndex + 1] : null

  // Build score lookup objects (value, good, bad, comments)
  // For category scoring: key by student's person ID (subject.id on the expanded subject)
  // For per-heat scoring: key by heat.id
  const value = {}
  const good = {}
  const bad = {}
  const comments = {}
  const scores = []

  hydratedHeats.forEach(heat => {
    if (heat.scores && heat.scores.length > 0) {
      heat.scores.forEach(score => {
        // For category scoring, use student's person ID (heat.subject.id)
        // For per-heat scoring, use heat.id
        const subjectId = (categoryScoringEnabled && heat.subject) ? heat.subject.id : heat.id

        value[subjectId] = score.value
        good[subjectId] = score.good
        bad[subjectId] = score.bad
        if (score.comments) {
          comments[subjectId] = score.comments
        }
        scores.push(score)
      })
    }
  })

  // Build data structure matching what the template expects
  return {
    event: event,
    judge: judge,
    number: heatNumber,
    style: style,
    subjects: hydratedHeats,
    heat: primaryHeat,
    dance: primaryHeat.dance_string,  // Use pre-computed dance string from server (e.g., "Closed Milonga")
    scoring: scoring,
    final: final,
    callbacks: callbacks,
    ballrooms: ballrooms,
    ballrooms_count: ballroomsCount,
    // Score lookup objects
    scores: scores,
    value: value,
    good: good,
    bad: bad,
    comments: comments,
    // Navigation
    prev: prev,
    next: next,
    // Additional fields from heats_show
    column_order: event.column_order,
    track_ages: event.track_ages,
    backnums: event.backnums,
    assign_judges: event.assign_judges,
    feedbacks: rawData.feedbacks || [],
    feedback_errors: rawData.feedback_errors || [],  // Server-computed validation errors
    showcase_logo: event.showcase_logo || '/intertwingly.png',
    show: judge.show_assignments || 'first',
    category_scoring_enabled: categoryScoringEnabled,
    category_score_assignments: categoryScoreAssignments,
    judge_present: judge.present || false,
    results: {},  // Empty results object for solo scoring
    // Server-computed paths (respects RAILS_APP_SCOPE)
    feedbacks_path: rawData.paths?.feedbacks,
    post_score_path: rawData.paths?.post_score,
    post_feedback_path: rawData.paths?.post_feedback,
    update_rank_path: rawData.paths?.update_rank,
    start_heat_path: rawData.paths?.start_heat,
    sort_scores_path: rawData.paths?.sort_scores,
    judge_person_path: rawData.paths?.judge_person,
    judge_toggle_present_path: rawData.paths?.judge_toggle_present,
    show_assignments_path: rawData.paths?.show_assignments,
    root_path: rawData.paths?.root,
    judge_heatlist_path: rawData.paths?.judge_heatlist
  }
}

/**
 * Build complete template data for the heat list
 * Groups heats by number and hydrates each heat
 * Used by both browser (heat_app_controller.js) and Node.js scripts
 */
export function buildHeatListTemplateData(rawData) {
  const lookups = buildLookupTables(rawData)

  // Group heats by number, take first heat for each number, and hydrate
  const heatsByNumber = {}
  rawData.heats.forEach(heat => {
    if (!heatsByNumber[heat.number]) {
      heatsByNumber[heat.number] = hydrateHeat(heat, lookups)
    }
  })

  // Return data with hydrated heats replacing raw heats
  return {
    ...rawData,
    heats: Object.values(heatsByNumber)
  }
}
