/**
 * SubjectSorter - Utility for sorting heat subjects by back number or level
 */

export class SubjectSorter {
  /**
   * Sort subjects according to judge preference
   * @param {Array} subjects - Array of subject objects
   * @param {string} sortOrder - 'back' or 'level'
   * @returns {Array} Sorted copy of subjects array
   */
  static sort(subjects, sortOrder = 'back') {
    // Make a copy to avoid mutating original
    const sortedSubjects = [...subjects]

    if (sortOrder === 'level') {
      return this.sortByLevel(sortedSubjects)
    } else {
      return this.sortByBack(sortedSubjects)
    }
  }

  /**
   * Sort by back number
   * Handles string/number conversion and null values
   */
  static sortByBack(subjects) {
    return subjects.sort((a, b) => {
      const backA = this.getBackNumber(a)
      const backB = this.getBackNumber(b)

      if (backA === null && backB === null) return 0
      if (backA === null) return 1  // Nulls to end
      if (backB === null) return -1

      return backA - backB
    })
  }

  /**
   * Sort by level/category
   * Groups by level, then by back within each level
   */
  static sortByLevel(subjects) {
    return subjects.sort((a, b) => {
      const levelA = this.getLevel(a)
      const levelB = this.getLevel(b)

      // Compare levels first
      if (levelA !== levelB) {
        if (levelA === null && levelB === null) return 0
        if (levelA === null) return 1  // Nulls to end
        if (levelB === null) return -1
        return levelA.localeCompare(levelB)
      }

      // Same level - sort by back number
      const backA = this.getBackNumber(a)
      const backB = this.getBackNumber(b)

      if (backA === null && backB === null) return 0
      if (backA === null) return 1
      if (backB === null) return -1

      return backA - backB
    })
  }

  /**
   * Extract back number from subject
   * Handles both direct back property and nested lead.back
   */
  static getBackNumber(subject) {
    // Try subject.lead.back first (most common)
    if (subject.lead?.back) {
      const back = parseInt(subject.lead.back, 10)
      return isNaN(back) ? null : back
    }

    // Try subject.back (fallback)
    if (subject.back) {
      const back = parseInt(subject.back, 10)
      return isNaN(back) ? null : back
    }

    return null
  }

  /**
   * Extract level name from subject
   * Returns level name or category name
   */
  static getLevel(subject) {
    // Try subject.level?.name first
    if (subject.level?.name) {
      return subject.level.name
    }

    // Try subject.subject_lvlcat (category name)
    if (subject.subject_lvlcat) {
      return subject.subject_lvlcat
    }

    // Try subject.category?.name
    if (subject.category?.name) {
      return subject.category.name
    }

    return null
  }
}
