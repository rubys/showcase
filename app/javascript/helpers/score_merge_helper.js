/**
 * ScoreMergeHelper - Score field merging logic
 *
 * Handles merging of score updates with current values for offline saves
 * and generating optimistic update responses.
 */

class ScoreMergeHelper {
  /**
   * Merge score update with current values for offline storage
   *
   * @param {Object} update - The score update {score?, value?, good?, bad?, comments?}
   * @param {Object} current - Current score values {value?, good?, bad?, comments?}
   * @returns {Object} Merged data for offline storage {score, comments, good, bad}
   */
  static mergeForOffline(update, current = {}) {
    // Ensure current is an object (handle null/undefined)
    const currentScore = current || {};

    // For feedback toggle: if update has computed toggle values in current,
    // prefer those over the single clicked value in update
    // This handles the case where FeedbackPanel sends clicked value for online
    // but provides computed toggle values for offline merge
    let good, bad;

    if (update.good !== undefined && currentScore._computedGood !== undefined) {
      // Use computed toggle value from currentScore
      good = currentScore._computedGood;
      bad = currentScore._computedBad || '';
    } else if (update.bad !== undefined && currentScore._computedBad !== undefined) {
      // Use computed toggle value from currentScore
      bad = currentScore._computedBad;
      good = currentScore._computedGood || '';
    } else {
      // Standard merge: prefer update over current
      good = update.good !== undefined ? update.good : (currentScore.good || '');
      bad = update.bad !== undefined ? update.bad : (currentScore.bad || '');
    }

    return {
      score: update.score || update.value || currentScore.value || '',
      comments: update.comments !== undefined ? update.comments : (currentScore.comments || ''),
      good,
      bad
    };
  }

  /**
   * Generate optimistic update response (only fields that were updated)
   *
   * @param {Object} update - The score update {score?, value?, good?, bad?, comments?}
   * @returns {Object} Response with only updated fields {value?, good?, bad?, comments?}
   */
  static generateOptimisticResponse(update) {
    const result = {};

    if (update.value !== undefined || update.score !== undefined) {
      result.value = update.value || update.score;
    }
    if (update.good !== undefined) {
      result.good = update.good;
    }
    if (update.bad !== undefined) {
      result.bad = update.bad;
    }
    if (update.comments !== undefined) {
      result.comments = update.comments;
    }

    return result;
  }

  /**
   * Normalize score field names (score → value)
   *
   * @param {Object} data - Data with possibly mixed field names
   * @returns {Object} Data with normalized field names
   */
  static normalizeFieldNames(data) {
    const normalized = { ...data };

    // If score field exists, convert to value (value takes precedence if both exist)
    if (normalized.score !== undefined) {
      if (normalized.value === undefined) {
        normalized.value = normalized.score;
      }
      delete normalized.score;
    }

    return normalized;
  }
}

export default ScoreMergeHelper;
