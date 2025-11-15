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
