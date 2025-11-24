#!/usr/bin/env node
// Standalone script to fetch normalized data and hydrate into per-heat structures
//
// Usage:
//   node scripts/hydrate_heats.mjs judge_id [style] [database]
//
// Examples:
//   node scripts/hydrate_heats.mjs 83 radio
//   node scripts/hydrate_heats.mjs 83 radio db/2025-barcelona-november.sqlite3
//
// This script fetches /scores/:judge/heats/data (normalized) and produces
// the same structure as /scores/:judge/heats/:heat (denormalized) but for ALL heats

import { execSync } from 'child_process'
import { readFileSync } from 'fs'

const judgeId = process.argv[2]
const style = process.argv[3] || 'radio'
const database = process.argv[4] || process.env.RAILS_APP_DB

if (!judgeId) {
  console.error('Usage: node scripts/hydrate_heats.mjs judge_id [style] [database]')
  console.error('   or: RAILS_APP_DB=database node scripts/hydrate_heats.mjs judge_id [style]')
  process.exit(1)
}

// Fetch normalized data using bin/run (no server needed)
async function fetchNormalizedData() {
  console.error(`Fetching normalized data for judge ${judgeId}...`)

  try {
    // Use bin/run with fetch_heats_data.rb script
    const dbPath = database || 'db/2025-barcelona-november.sqlite3'
    const cmd = `bin/run ${dbPath} scripts/fetch_heats_data.rb ${judgeId} ${style}`

    const result = execSync(cmd, { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'inherit'] })
    const data = JSON.parse(result.trim())
    console.error(`✓ Loaded normalized data: ${data.heats.length} heats, ${Object.keys(data.scores).length} scores`)
    return data
  } catch (error) {
    console.error('bin/run failed:', error.message)
    throw error
  }
}

// Hydrate a single heat into the per-heat structure
// This implements the same business logic as ScoresController#heat
function hydrateHeat(normalizedData, heatNumber) {
  const { event, judge, heats, entries, people, dances, scores, feedbacks } = normalizedData

  // Find all heats with this number (there can be multiple due to database structure)
  const heatRecords = heats.filter(h => h.number === heatNumber)
  if (heatRecords.length === 0) {
    throw new Error(`Heat ${heatNumber} not found`)
  }

  // Get primary heat record
  const primaryHeatRecord = heatRecords[0]
  const dance = dances[primaryHeatRecord.dance_id]
  const category = primaryHeatRecord.category

  // Hydrate each heat record with full references
  // NOTE: In the Rails controller, these are Heat objects. We're building similar structures.
  let subjects = heatRecords.map(heatRecord => {
    const entry = entries[heatRecord.entry_id]

    // Hydrate people with studios
    const hydratePerson = (personId) => {
      if (!personId) return null
      const person = people[personId]
      const studio = person.studio_id ? normalizedData.studios[person.studio_id] : null
      return { ...person, studio }
    }

    const lead = hydratePerson(entry.lead_id)
    const follow = hydratePerson(entry.follow_id)
    const instructor = hydratePerson(entry.instructor_id)
    const pro = hydratePerson(entry.pro_id)

    const age = entry.age_id ? normalizedData.ages[entry.age_id] : null
    const level = entry.level_id ? normalizedData.levels[entry.level_id] : null

    // Get scores for this heat (scores is an object indexed by score ID)
    // For category scoring, scores are stored with heat_id = -category_id
    let heatScores = Object.values(scores).filter(s => s.heat_id === heatRecord.id && s.judge_id === judge.id)

    // If no direct heat scores and category scoring is enabled, look for category scores
    // Category scores will be matched to subjects later based on person_id
    if (heatScores.length === 0 && dance.category_id) {
      // We'll handle category score lookup per-subject after identifying students
      heatScores = []
    }

    // Build subject structure (before category scoring expansion)
    return {
      id: heatRecord.id,
      number: heatRecord.number,
      dance_id: heatRecord.dance_id,
      dance: dance,
      category: heatRecord.category,
      entry: {
        id: entry.id,
        lead_id: entry.lead_id,
        follow_id: entry.follow_id,
        instructor_id: entry.instructor_id,
        pro_id: entry.pro_id,
        studio_id: entry.studio_id,
        lead: lead,
        follow: follow,
        instructor: instructor,
        pro: pro,
        age: age,
        level: level
      },
      lead: lead,
      follow: follow,
      scores: heatScores,
      original_heat: heatRecord
    }
  })

  // Determine which category_id to use based on heat category
  let categoryId = null
  if (category === 'Closed') {
    categoryId = dance.closed_category_id
  } else if (category === 'Open') {
    categoryId = dance.open_category_id || dance.pro_open_category_id
  } else if (category === 'Solo') {
    categoryId = dance.solo_category_id || dance.pro_solo_category_id
  } else if (category === 'Multi') {
    categoryId = dance.multi_category_id || dance.pro_multi_category_id
  }

  // Check if category scoring is enabled (server provides this)
  const categoryRecord = categoryId ? normalizedData.categories?.[categoryId] : null
  const categoryScoringEnabled = event.student_judge_assignments && categoryRecord?.use_category_scoring

  // Apply category scoring expansion if enabled
  // This mirrors the logic in ScoresController#heat lines 796-850
  if (categoryScoringEnabled) {
    const expandedSubjects = []

    // Build lookup for category scores: heat_id = -category_id, keyed by person_id
    const categoryScores = {}
    if (categoryId) {
      Object.values(scores).forEach(score => {
        if (score.heat_id === -categoryId && score.judge_id === judge.id && score.person_id) {
          categoryScores[score.person_id] = [score]
        }
      })
    }

    subjects.forEach(subject => {
      const students = []

      // Identify students in this couple
      if (subject.lead.type === 'Student') {
        students.push({ student: subject.lead, role: 'lead' })
      }
      if (subject.follow.type === 'Student') {
        students.push({ student: subject.follow, role: 'follow' })
      }

      if (students.length === 2) {
        // Amateur couple - create two entries, one for each student
        students.forEach(studentInfo => {
          // Get category score for this student
          const studentScores = categoryScores[studentInfo.student.id] || []

          expandedSubjects.push({
            id: subject.id,
            number: subject.number,
            dance_id: subject.dance_id,
            dance: subject.dance,
            category: subject.category,
            entry: subject.entry,
            lead: subject.lead,
            follow: subject.follow,
            subject: studentInfo.student,  // The student being scored
            student_role: studentInfo.role, // 'lead' or 'follow'
            scores: studentScores,  // Category score for this student
            original_heat: subject.original_heat
          })
        })
      } else if (students.length === 1) {
        // Single student - keep as-is but mark the student
        const studentScores = categoryScores[students[0].student.id] || []

        expandedSubjects.push({
          id: subject.id,
          number: subject.number,
          dance_id: subject.dance_id,
          dance: subject.dance,
          category: subject.category,
          entry: subject.entry,
          lead: subject.lead,
          follow: subject.follow,
          subject: students[0].student,
          student_role: students[0].role,
          scores: studentScores,  // Category score for this student
          original_heat: subject.original_heat
        })
      } else {
        // Pro/Am - no students, keep as-is
        // Determine subject based on who is the student (default to lead if none)
        const subjectPerson = subject.lead.type === 'Student' ? subject.lead :
                              subject.follow.type === 'Student' ? subject.follow :
                              subject.lead

        expandedSubjects.push({
          id: subject.id,
          number: subject.number,
          dance_id: subject.dance_id,
          dance: subject.dance,
          category: subject.category,
          entry: subject.entry,
          lead: subject.lead,
          follow: subject.follow,
          subject: subjectPerson,
          student_role: null,
          scores: subject.scores,
          original_heat: subject.original_heat
        })
      }
    })

    subjects = expandedSubjects
  } else {
    // No category scoring - just add subject field to each
    subjects = subjects.map(subject => {
      const subjectPerson = subject.lead.type === 'Student' ? subject.lead :
                            subject.follow.type === 'Student' ? subject.follow :
                            subject.lead
      return {
        ...subject,
        subject: subjectPerson,
        student_role: null
      }
    })
  }

  // Build category score assignments set (student IDs that have category scores)
  // Server provides all assignments for this category, but we need to filter to only
  // include students that are in THIS heat (matches Rails logic at line 865)
  const allCategoryAssignments = categoryId && normalizedData.category_score_assignments?.[categoryId]
    ? new Set(normalizedData.category_score_assignments[categoryId])
    : new Set()

  const categoryScoreAssignments = []
  subjects.forEach(subject => {
    const studentId = subject.subject?.id
    if (studentId && allCategoryAssignments.has(studentId)) {
      if (!categoryScoreAssignments.includes(studentId)) {
        categoryScoreAssignments.push(studentId)
      }
    }
  })

  // Build ballrooms grouping
  const ballrooms = {}
  subjects.forEach(subject => {
    const ballroom = subject.original_heat.ballroom || 1
    if (!ballrooms[ballroom]) {
      ballrooms[ballroom] = []
    }
    ballrooms[ballroom].push(subject)
  })
  const ballroomsCount = Object.keys(ballrooms).length

  // Build score lookup objects (value/good/bad/comments by subject ID)
  const value = {}
  const good = {}
  const bad = {}
  const comments = {}

  subjects.forEach(subject => {
    if (subject.scores && subject.scores.length > 0) {
      const score = subject.scores[0]
      if (score.value !== undefined && score.value !== null) value[subject.id] = score.value
      if (score.good !== undefined && score.good !== null) good[subject.id] = score.good
      if (score.bad !== undefined && score.bad !== null) bad[subject.id] = score.bad
      if (score.comments !== undefined && score.comments !== null) comments[subject.id] = score.comments
    }
  })

  // Calculate prev/next navigation
  const allHeatNumbers = [...new Set(heats.map(h => h.number))].sort((a, b) => a - b)
  const currentIndex = allHeatNumbers.indexOf(heatNumber)
  const prev = currentIndex > 0 ? allHeatNumbers[currentIndex - 1] : null
  const next = currentIndex < allHeatNumbers.length - 1 ? allHeatNumbers[currentIndex + 1] : null

  // Create primary heat object (combines first subject with heat-level properties)
  const primaryHeat = subjects[0] ? {
    ...subjects[0],
    category: category
  } : null

  // Compute dance name with category prefix (e.g. "Closed Swing")
  const danceName = category && dance?.name ? `${category} ${dance.name}` : dance?.name

  // Compute scoring type based on category (matches Rails logic)
  let scoring
  if (category === 'Solo') {
    scoring = event.solo_scoring
  } else if (category === 'Multi') {
    scoring = event.multi_scoring
  } else if (category === 'Open' || (category === 'Closed' && event.closed_scoring === '=') || event.heat_range_cat > 0) {
    scoring = event.open_scoring
  } else {
    scoring = event.closed_scoring
  }

  // Return structure matching per-heat endpoint
  return {
    event: event,
    judge: judge,
    judge_display_name: judge.display_name,
    number: heatNumber,
    style: style,
    subjects: subjects,
    heat: primaryHeat,
    dance: danceName,
    scoring: scoring,
    final: primaryHeatRecord.final || false,
    callbacks: primaryHeatRecord.callbacks || false,
    ballrooms: ballrooms,
    ballrooms_count: ballroomsCount,
    scores: subjects.flatMap(s => s.scores || []),
    value: value,
    good: good,
    bad: bad,
    comments: comments,
    prev: prev,
    next: next,
    column_order: event.column_order,
    track_ages: event.track_ages,
    backnums: event.backnums,
    assign_judges: event.assign_judges,
    feedbacks: feedbacks || [],
    showcase_logo: event.showcase_logo || '/intertwingly.png',
    category_scoring_enabled: categoryScoringEnabled,
    category_score_assignments: categoryScoreAssignments,
    show: judge.show_assignments || 'first',
    judge_present: judge.present || false
  }
}

// Main execution (only when run as script, not when imported)
async function main() {
  try {
    const normalizedData = await fetchNormalizedData()

    // Get unique heat numbers
    const heatNumbers = [...new Set(normalizedData.heats.map(h => h.number))].sort((a, b) => a - b)
    console.error(`Found ${heatNumbers.length} unique heat numbers`)

    // Hydrate all heats
    const hydratedHeats = heatNumbers.map(heatNumber => {
      return hydrateHeat(normalizedData, heatNumber)
    })

    console.error(`✓ Hydrated ${hydratedHeats.length} heats`)

    // Output the result as JSON (to stdout)
    console.log(JSON.stringify({
      heats: hydratedHeats,
      // Include common data for easy access
      event: normalizedData.event,
      judge: normalizedData.judge,
      style: style
    }, null, 2))

  } catch (error) {
    console.error('Error:', error.message)
    console.error(error.stack)
    process.exit(1)
  }
}

// Export functions for use as module
export { hydrateHeat }

// Only run main() when executed as a script (not when imported)
if (import.meta.url === `file://${process.argv[1]}`) {
  main()
}
