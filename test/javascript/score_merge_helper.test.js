import { describe, it, expect } from 'vitest'
import ScoreMergeHelper from '../../app/javascript/helpers/score_merge_helper'

describe('ScoreMergeHelper', () => {
  describe('mergeForOffline', () => {
    it('merges partial update with current values', () => {
      const update = { good: 'F P' }
      const current = { value: '3', good: 'F', bad: '', comments: 'test' }

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.score).toBe('3')  // Preserved from current.value
      expect(merged.good).toBe('F P')  // Updated
      expect(merged.bad).toBe('')  // Preserved
      expect(merged.comments).toBe('test')  // Preserved
    })

    it('handles empty current values', () => {
      const update = { value: '4', good: 'T' }
      const current = {}

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.score).toBe('4')
      expect(merged.good).toBe('T')
      expect(merged.bad).toBe('')  // Default
      expect(merged.comments).toBe('')  // Default
    })

    it('prefers score over value in update', () => {
      const update = { score: 'S', value: '5' }

      const merged = ScoreMergeHelper.mergeForOffline(update, {})

      expect(merged.score).toBe('S')
    })

    it('preserves undefined fields from current', () => {
      const update = { value: '2' }
      const current = { value: '1', good: 'F P', bad: 'T', comments: 'Nice' }

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.score).toBe('2')
      expect(merged.good).toBe('F P')
      expect(merged.bad).toBe('T')
      expect(merged.comments).toBe('Nice')
    })

    it('handles null current parameter', () => {
      const update = { value: '3', good: 'F' }

      const merged = ScoreMergeHelper.mergeForOffline(update, null)

      expect(merged.score).toBe('3')
      expect(merged.good).toBe('F')
      expect(merged.bad).toBe('')
      expect(merged.comments).toBe('')
    })

    it('handles explicit empty string updates', () => {
      const update = { good: '', bad: '', comments: '' }
      const current = { value: '3', good: 'F', bad: 'T', comments: 'test' }

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.score).toBe('3')
      expect(merged.good).toBe('')  // Explicitly cleared
      expect(merged.bad).toBe('')  // Explicitly cleared
      expect(merged.comments).toBe('')  // Explicitly cleared
    })

    it('uses _computedGood when toggling good feedback', () => {
      // Simulates clicking "T" in good column when current good is "LF T" and bad is "F"
      // Clicked value is "T", but computed toggle value is "LF" (removing T)
      const update = { good: 'T' }  // Clicked value
      const current = {
        value: '3',
        good: 'LF T',
        bad: 'F',
        _computedGood: 'LF',  // Computed: removed T from good
        _computedBad: 'F'  // Computed: bad unchanged (T not in bad)
      }

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.score).toBe('3')
      expect(merged.good).toBe('LF')  // Uses _computedGood, not update.good
      expect(merged.bad).toBe('F')  // Uses _computedBad
      expect(merged.comments).toBe('')
    })

    it('uses _computedBad when toggling bad feedback', () => {
      // Simulates clicking "F" in bad column when current good is "LF T" and bad is ""
      // Clicked value is "F", but computed values handle mutual exclusivity
      const update = { bad: 'F' }  // Clicked value
      const current = {
        value: '5',
        good: 'LF T',
        bad: '',
        _computedGood: 'LF T',  // Computed: good unchanged (F not in good)
        _computedBad: 'F'  // Computed: added F to bad
      }

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.score).toBe('5')
      expect(merged.good).toBe('LF T')  // Uses _computedGood
      expect(merged.bad).toBe('F')  // Uses _computedBad, not update.bad
      expect(merged.comments).toBe('')
    })

    it('uses _computed values with mutual exclusivity', () => {
      // Simulates clicking "F" in good column when F is currently in bad
      // Mutual exclusivity: F should move from bad to good
      const update = { good: 'F' }  // Clicked value
      const current = {
        value: '5',
        good: 'LF T',
        bad: 'F',
        _computedGood: 'LF T F',  // Computed: added F to good
        _computedBad: ''  // Computed: removed F from bad (mutual exclusivity)
      }

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.score).toBe('5')
      expect(merged.good).toBe('LF T F')  // Uses _computedGood
      expect(merged.bad).toBe('')  // Uses _computedBad (F removed)
      expect(merged.comments).toBe('')
    })

    it('falls back to standard merge when _computed fields absent', () => {
      // When no _computed fields, should use normal merge behavior
      const update = { good: 'F' }
      const current = { value: '3', good: 'LF T', bad: 'T' }

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.score).toBe('3')
      expect(merged.good).toBe('F')  // Uses update.good (standard behavior)
      expect(merged.bad).toBe('T')  // Uses current.bad (standard behavior)
      expect(merged.comments).toBe('')
    })

    it('handles _computedBad as empty string', () => {
      // When computed bad is empty (mutual exclusivity removed all bad feedback)
      const update = { good: 'F' }
      const current = {
        value: '4',
        good: 'LF',
        bad: 'F T',
        _computedGood: 'LF F',
        _computedBad: ''  // Empty string, not undefined
      }

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.good).toBe('LF F')
      expect(merged.bad).toBe('')  // Uses _computedBad (empty string)
    })
  })

  describe('generateOptimisticResponse', () => {
    it('returns only updated fields', () => {
      const update = { value: '3', good: 'F' }

      const response = ScoreMergeHelper.generateOptimisticResponse(update)

      expect(response.value).toBe('3')
      expect(response.good).toBe('F')
      expect(response.bad).toBeUndefined()
      expect(response.comments).toBeUndefined()
    })

    it('handles empty update', () => {
      const update = {}

      const response = ScoreMergeHelper.generateOptimisticResponse(update)

      expect(Object.keys(response)).toHaveLength(0)
    })

    it('handles score field instead of value', () => {
      const update = { score: 'S' }

      const response = ScoreMergeHelper.generateOptimisticResponse(update)

      expect(response.value).toBe('S')
      expect(response.score).toBeUndefined()
    })

    it('prefers value over score when both present', () => {
      const update = { value: '4', score: 'S' }

      const response = ScoreMergeHelper.generateOptimisticResponse(update)

      expect(response.value).toBe('4')
    })

    it('includes all feedback fields when present', () => {
      const update = { value: '3', good: 'F P', bad: 'T', comments: 'Nice try' }

      const response = ScoreMergeHelper.generateOptimisticResponse(update)

      expect(response.value).toBe('3')
      expect(response.good).toBe('F P')
      expect(response.bad).toBe('T')
      expect(response.comments).toBe('Nice try')
    })

    it('handles explicit empty strings', () => {
      const update = { good: '', bad: '', comments: '' }

      const response = ScoreMergeHelper.generateOptimisticResponse(update)

      expect(response.good).toBe('')
      expect(response.bad).toBe('')
      expect(response.comments).toBe('')
      expect(response.value).toBeUndefined()
    })
  })

  describe('normalizeFieldNames', () => {
    it('converts score to value', () => {
      const data = { score: 'S', good: 'F' }

      const normalized = ScoreMergeHelper.normalizeFieldNames(data)

      expect(normalized.value).toBe('S')
      expect(normalized.score).toBeUndefined()
      expect(normalized.good).toBe('F')
    })

    it('preserves value when both score and value present', () => {
      const data = { score: 'S', value: '4', good: 'F' }

      const normalized = ScoreMergeHelper.normalizeFieldNames(data)

      expect(normalized.value).toBe('4')
      expect(normalized.score).toBeUndefined()
      expect(normalized.good).toBe('F')
    })

    it('does not modify data without score field', () => {
      const data = { value: '3', good: 'F' }

      const normalized = ScoreMergeHelper.normalizeFieldNames(data)

      expect(normalized.value).toBe('3')
      expect(normalized.score).toBeUndefined()
      expect(normalized.good).toBe('F')
    })

    it('returns new object (does not mutate input)', () => {
      const data = { score: 'S', good: 'F' }

      const normalized = ScoreMergeHelper.normalizeFieldNames(data)

      expect(data.score).toBe('S')  // Original unchanged
      expect(data.value).toBeUndefined()
      expect(normalized.value).toBe('S')  // Normalized has value
      expect(normalized.score).toBeUndefined()
    })
  })
})
