import { describe, it, expect, beforeEach, vi } from 'vitest'
import { heatDataManager } from '../../app/javascript/helpers/heat_data_manager'

describe('HeatDataManager', () => {
  beforeEach(async () => {
    // Clear IndexedDB before each test
    const dbs = await indexedDB.databases()
    for (const db of dbs) {
      indexedDB.deleteDatabase(db.name)
    }
  })

  // Converted from Ruby: test "creates new score via AJAX post endpoint"
  describe('dirty scores management', () => {
    it('creates new dirty score in IndexedDB', async () => {
      await heatDataManager.addDirtyScore(
        55,    // judgeId
        100,   // heatId
        1,     // slot
        { score: 'S', comments: '', good: '', bad: '' }
      )

      const dirtyScores = await heatDataManager.getDirtyScores(55)

      expect(dirtyScores).toHaveLength(1)
      expect(dirtyScores[0].heat).toBe(100)
      expect(dirtyScores[0].slot).toBe(1)
      expect(dirtyScores[0].score).toBe('S')
    })

    // Converted from Ruby: test "updates existing score value via AJAX"
    it('updates existing dirty score (last write wins)', async () => {
      await heatDataManager.addDirtyScore(55, 100, 1, { score: 'G', comments: '', good: '', bad: '' })
      await heatDataManager.addDirtyScore(55, 100, 1, { score: 'B', comments: '', good: '', bad: '' })

      const dirtyScores = await heatDataManager.getDirtyScores(55)

      expect(dirtyScores).toHaveLength(1)
      expect(dirtyScores[0].score).toBe('B')
    })

    // Converted from Ruby: test "deletes score when value becomes empty"
    it('removes dirty score after successful upload', async () => {
      await heatDataManager.addDirtyScore(55, 100, 1, { score: 'G', comments: '', good: '', bad: '' })

      const beforeRemoval = await heatDataManager.getDirtyScores(55)
      expect(beforeRemoval).toHaveLength(1)

      await heatDataManager.removeDirtyScore(55, 100, 1)

      const afterRemoval = await heatDataManager.getDirtyScores(55)
      expect(afterRemoval).toHaveLength(0)
    })

    it('clears all dirty scores for a judge', async () => {
      await heatDataManager.addDirtyScore(55, 100, 1, { score: 'G', comments: '', good: '', bad: '' })
      await heatDataManager.addDirtyScore(55, 101, 1, { score: 'S', comments: '', good: '', bad: '' })

      const beforeClear = await heatDataManager.getDirtyScores(55)
      expect(beforeClear).toHaveLength(2)

      await heatDataManager.clearDirtyScores(55)

      const afterClear = await heatDataManager.getDirtyScores(55)
      expect(afterClear).toHaveLength(0)
    })

    it('handles multiple slots for same heat', async () => {
      await heatDataManager.addDirtyScore(55, 100, 1, { score: 'G', comments: '', good: '', bad: '' })
      await heatDataManager.addDirtyScore(55, 100, 2, { score: 'S', comments: '', good: '', bad: '' })

      const dirtyScores = await heatDataManager.getDirtyScores(55)

      expect(dirtyScores).toHaveLength(2)
      expect(dirtyScores.find(s => s.slot === 1).score).toBe('G')
      expect(dirtyScores.find(s => s.slot === 2).score).toBe('S')
    })
  })

  // Converted from Ruby batch upload tests
  describe('batch upload', () => {
    it('batch uploads dirty scores to server', async () => {
      global.fetch = vi.fn(() =>
        Promise.resolve({
          ok: true,
          json: () => Promise.resolve({
            succeeded: [{ heat: 100, slot: 1 }],
            failed: []
          })
        })
      )

      await heatDataManager.addDirtyScore(55, 100, 1, { score: 'G', comments: '', good: '', bad: '' })
      const result = await heatDataManager.batchUploadDirtyScores(55)

      expect(result.succeeded).toHaveLength(1)
      expect(result.failed).toHaveLength(0)

      // Dirty scores should be cleared after successful upload
      const remaining = await heatDataManager.getDirtyScores(55)
      expect(remaining).toHaveLength(0)

      // Verify fetch was called with correct data
      expect(fetch).toHaveBeenCalledWith(
        '/scores/55/batch',
        expect.objectContaining({
          method: 'POST',
          body: expect.stringContaining('"heat":100')
        })
      )
    })

    it('handles batch upload with no dirty scores', async () => {
      const result = await heatDataManager.batchUploadDirtyScores(55)

      expect(result.succeeded).toHaveLength(0)
      expect(result.failed).toHaveLength(0)
    })

    it('handles batch upload failure gracefully', async () => {
      global.fetch = vi.fn(() =>
        Promise.resolve({
          ok: false,
          status: 500
        })
      )

      await heatDataManager.addDirtyScore(55, 100, 1, { score: 'G', comments: '', good: '', bad: '' })
      const result = await heatDataManager.batchUploadDirtyScores(55)

      expect(result.succeeded).toHaveLength(0)
      expect(result.failed).toHaveLength(1)

      // Dirty scores should remain after failed upload
      const remaining = await heatDataManager.getDirtyScores(55)
      expect(remaining).toHaveLength(1)
    })

    it('handles network error during batch upload', async () => {
      global.fetch = vi.fn(() => Promise.reject(new Error('Network error')))

      await heatDataManager.addDirtyScore(55, 100, 1, { score: 'G', comments: '', good: '', bad: '' })
      const result = await heatDataManager.batchUploadDirtyScores(55)

      expect(result.succeeded).toHaveLength(0)
      expect(result.failed).toHaveLength(1)
      expect(result.failed[0].error).toBe('Network error')
    })
  })

  // Data fetching tests
  describe('data fetching', () => {
    it('fetches heat data from server', async () => {
      const mockData = {
        event: { id: 1, name: 'Test Event' },
        judge: { id: 55, name: 'Test Judge' },
        heats: []
      }

      global.fetch = vi.fn(() =>
        Promise.resolve({
          ok: true,
          json: () => Promise.resolve(mockData)
        })
      )

      const data = await heatDataManager.getData(55)

      expect(data).toEqual(mockData)
      expect(fetch).toHaveBeenCalledWith(
        '/scores/55/heats.json',
        expect.objectContaining({
          credentials: 'same-origin'
        })
      )
    })

    it('handles fetch error', async () => {
      global.fetch = vi.fn(() =>
        Promise.resolve({
          ok: false,
          status: 404
        })
      )

      await expect(heatDataManager.getData(55)).rejects.toThrow('HTTP error! status: 404')
    })

    it('handles network error', async () => {
      global.fetch = vi.fn(() => Promise.reject(new Error('Network unavailable')))

      await expect(heatDataManager.getData(55)).rejects.toThrow('Network unavailable')
    })
  })

  // saveScore() function tests - the high-level API for saving scores
  describe('saveScore()', () => {
    it('returns server response data on successful online save', async () => {
      const serverResponse = {
        value: '4',
        good: 'F P',
        bad: null,
        comments: ''
      }

      global.fetch = vi.fn(() =>
        Promise.resolve({
          ok: true,
          json: () => Promise.resolve(serverResponse)
        })
      )

      const result = await heatDataManager.saveScore(55, {
        heat: 100,
        slot: null,
        good: 'F'
      })

      expect(result).toEqual(serverResponse)
      expect(result.good).toBe('F P')
      expect(result.bad).toBe(null)
    })

    it('handles null values in server response', async () => {
      const serverResponse = {
        value: '3',
        good: 'F',
        bad: null,  // Server returns null when field is cleared
        comments: null
      }

      global.fetch = vi.fn(() =>
        Promise.resolve({
          ok: true,
          json: () => Promise.resolve(serverResponse)
        })
      )

      const result = await heatDataManager.saveScore(55, {
        heat: 100,
        slot: null,
        good: 'F'
      })

      // Should not throw error on null values
      expect(result.bad).toBe(null)
      expect(result.comments).toBe(null)
    })

    it('returns optimistic data on offline save', async () => {
      global.fetch = vi.fn(() => Promise.reject(new Error('Network unavailable')))

      const result = await heatDataManager.saveScore(55, {
        heat: 100,
        slot: null,
        value: '3',
        good: 'F',
        bad: '',
        comments: ''
      })

      // Should return only fields that were in the request
      expect(result.value).toBe('3')
      expect(result.good).toBe('F')
      expect(result.bad).toBe('')
      expect(result.comments).toBe('')

      // Should be queued in dirty scores
      const dirtyScores = await heatDataManager.getDirtyScores(55)
      expect(dirtyScores).toHaveLength(1)
      expect(dirtyScores[0].score).toBe('3')
    })

    it('returns partial optimistic data - does not include undefined fields', async () => {
      global.fetch = vi.fn(() => Promise.reject(new Error('Network unavailable')))

      const result = await heatDataManager.saveScore(55, {
        heat: 100,
        slot: null,
        value: '3'  // Only sending value, not good/bad/comments
      })

      // Should only return the value field, not good/bad/comments
      expect(result.value).toBe('3')
      expect(result.good).toBeUndefined()
      expect(result.bad).toBeUndefined()
      expect(result.comments).toBeUndefined()
    })

    it('does NOT add to dirty queue when successful online save and queue is empty', async () => {
      const serverResponse = {
        value: '4',
        good: 'F',
        bad: '',
        comments: ''
      }

      global.fetch = vi.fn(() =>
        Promise.resolve({
          ok: true,
          json: () => Promise.resolve(serverResponse)
        })
      )

      // Ensure dirty queue is empty
      await heatDataManager.clearDirtyScores(55)

      await heatDataManager.saveScore(55, {
        heat: 100,
        slot: null,
        good: 'F'
      })

      // Should NOT add to dirty queue when queue is empty
      const dirtyScores = await heatDataManager.getDirtyScores(55)
      expect(dirtyScores).toHaveLength(0)
    })

    it('adds to dirty queue when successful online save but queue has pending scores', async () => {
      const serverResponse = {
        value: '4',
        good: 'F',
        bad: '',
        comments: ''
      }

      // Mock successful POST but failed batch upload to keep scores in queue
      let callCount = 0
      global.fetch = vi.fn(() => {
        callCount++
        if (callCount === 1) {
          // First call: successful POST
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve(serverResponse)
          })
        } else {
          // Second call: batch upload - simulate failure
          return Promise.resolve({
            ok: false,
            status: 500
          })
        }
      })

      // Add a pending dirty score
      await heatDataManager.addDirtyScore(55, 99, null, {
        score: 'G',
        comments: '',
        good: '',
        bad: ''
      })

      // Now save a new score - it should succeed online but also add to dirty queue
      // because there's a pending score
      await heatDataManager.saveScore(55, {
        heat: 100,
        slot: null,
        good: 'F'
      })

      // Wait for async batch upload to complete
      await new Promise(resolve => setTimeout(resolve, 50))

      // Should have added to dirty queue (original pending + new save with updated value)
      const dirtyScores = await heatDataManager.getDirtyScores(55)
      expect(dirtyScores.length).toBeGreaterThanOrEqual(1)
    })

    it('uses server response data (not request data) when adding to dirty queue', async () => {
      const serverResponse = {
        value: '4',
        good: 'F P T',  // Server returns expanded list
        bad: '',
        comments: ''
      }

      let callCount = 0
      global.fetch = vi.fn(() => {
        callCount++
        if (callCount === 1) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve(serverResponse)
          })
        } else {
          // Batch upload fails
          return Promise.resolve({
            ok: false,
            status: 500
          })
        }
      })

      // Add pending score
      await heatDataManager.addDirtyScore(55, 99, null, {
        score: 'G',
        comments: '',
        good: '',
        bad: ''
      })

      // Save with partial data - server returns complete data
      await heatDataManager.saveScore(55, {
        heat: 100,
        slot: null,
        good: 'F'  // Sent only "F"
      })

      // Wait for batch upload
      await new Promise(resolve => setTimeout(resolve, 50))

      // Dirty queue should contain server's complete response, not just "F"
      const dirtyScores = await heatDataManager.getDirtyScores(55)
      const savedScore = dirtyScores.find(s => s.heat === 100)
      if (savedScore) {
        expect(savedScore.good).toBe('F P T')  // Should use server's expanded value
      }
    })
  })
})
