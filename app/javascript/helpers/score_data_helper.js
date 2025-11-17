/**
 * ScoreDataHelper - Shared utilities for extracting score metadata
 *
 * Provides helper functions for heat components to access score data
 * and extract metadata like person_id for category scoring.
 */

/**
 * Find a subject by heat ID in a data structure
 * @param {Object} data - Can be:
 *   - { subjects: [...] } for heat-solo and heat-rank
 *   - { [ballroom]: [...subjects...] } for heat-table (ballrooms object)
 *   - { [score]: [...subjects...] } for heat-cards (results object)
 * @param {number} heatId - The heat ID to find
 * @returns {Object|null} The subject or null if not found
 */
export function findSubject(data, heatId) {
  if (!data || typeof data !== 'object') {
    return null;
  }

  // Direct subjects array (solo, rank)
  if (data.subjects && Array.isArray(data.subjects)) {
    return data.subjects.find(s => s.id === heatId) || null;
  }

  // Object with arrays as values (table ballrooms, cards results)
  for (const subjects of Object.values(data)) {
    if (Array.isArray(subjects)) {
      const subject = subjects.find(s => s.id === heatId);
      if (subject) return subject;
    }
  }

  return null;
}

/**
 * Get existing score for a subject from a specific judge
 * @param {Object} subject - The subject object
 * @param {number} judgeId - The judge ID
 * @returns {Object|null} The score or null if not found
 */
export function getSubjectScore(subject, judgeId) {
  if (!subject || !subject.scores) return null;
  return subject.scores.find(s => s.judge_id === judgeId) || null;
}

/**
 * Enhance score data with person_id and student_id if category scoring is enabled
 * @param {Object} data - The score data to enhance (mutated in place)
 * @param {Object} dataSource - Data structure containing subjects
 * @param {number} heatId - The heat ID
 * @param {number} judgeId - The judge ID
 * @returns {Object} The enhanced data object (same reference as input)
 */
export function enhanceWithPersonId(data, dataSource, heatId, judgeId) {
  const subject = findSubject(dataSource, heatId);
  if (subject) {
    const score = getSubjectScore(subject, judgeId);
    if (score?.person_id) {
      data.person_id = score.person_id;
    }
    // Add student_id for amateur couples with category scoring
    if (subject.student_id) {
      data.student_id = subject.student_id;
    }
  }
  return data;
}
