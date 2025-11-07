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
})
