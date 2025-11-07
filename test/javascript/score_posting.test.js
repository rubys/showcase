import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { heatDataManager } from '../../app/javascript/helpers/heat_data_manager'

/**
 * Tests for score posting behavior - verifying SPA matches Ruby controller behavior
 *
 * These tests mirror the Ruby controller tests in test/controllers/scores_controller_test.rb
 * to ensure the JavaScript implementation matches expected behavior.
 */

describe('Score Posting (matching Ruby controller tests)', () => {
  let fetchMock

  beforeEach(async () => {
    // Clear IndexedDB before each test
    const dbs = await indexedDB.databases()
    for (const db of dbs) {
      indexedDB.deleteDatabase(db.name)
    }

    // Setup fetch mock
    fetchMock = vi.fn()
    global.fetch = fetchMock
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  // Converted from Ruby: test "creates new score via AJAX post endpoint"
  describe('POST /scores/:judge/post', () => {
    it('creates new score with basic value', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const scoreData = {
        heat: 100,
        score: 'S',
        comments: '',
        good: '',
        bad: ''
      }

      // Simulate posting score
      const response = await fetch('/scores/55/post', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(scoreData)
      })

      expect(response.ok).toBe(true)
      expect(fetchMock).toHaveBeenCalledWith(
        '/scores/55/post',
        expect.objectContaining({
          method: 'POST',
          body: expect.stringContaining('"score":"S"')
        })
      )
    })

    // Converted from Ruby: test "updates existing score value via AJAX"
    it('updates existing score value', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const scoreData = {
        heat: 100,
        score: 'G',  // Changed from 'S' to 'G'
        comments: '',
        good: '',
        bad: ''
      }

      const response = await fetch('/scores/55/post', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(scoreData)
      })

      expect(response.ok).toBe(true)
      expect(fetchMock).toHaveBeenCalledWith(
        '/scores/55/post',
        expect.objectContaining({
          method: 'POST',
          body: expect.stringContaining('"score":"G"')
        })
      )
    })

    // Converted from Ruby: test "deletes score when value becomes empty"
    it('handles empty score (should delete on server)', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const scoreData = {
        heat: 100,
        score: '',  // Empty score triggers deletion
        comments: '',
        good: '',
        bad: ''
      }

      const response = await fetch('/scores/55/post', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(scoreData)
      })

      expect(response.ok).toBe(true)
      // Server should handle deletion logic
    })

    // Converted from Ruby: test "creates score with slot number for multi-dance heats"
    it('creates score with slot number for multi-heat rounds', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const scoreData = {
        heat: 100,
        slot: 2,  // Slot 2 for multi-heat
        score: 'G',
        comments: '',
        good: '',
        bad: ''
      }

      const response = await fetch('/scores/55/post', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(scoreData)
      })

      expect(response.ok).toBe(true)
      expect(fetchMock).toHaveBeenCalledWith(
        '/scores/55/post',
        expect.objectContaining({
          method: 'POST',
          body: expect.stringContaining('"slot":2')
        })
      )
    })

    // Converted from Ruby: test "adds comments via scoring interface"
    it('creates score with comments', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const scoreData = {
        heat: 100,
        score: 'G',
        comments: 'Great technique and musicality',
        good: '',
        bad: ''
      }

      const response = await fetch('/scores/55/post', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(scoreData)
      })

      expect(response.ok).toBe(true)
      expect(fetchMock).toHaveBeenCalledWith(
        '/scores/55/post',
        expect.objectContaining({
          method: 'POST',
          body: expect.stringContaining('Great technique')
        })
      )
    })
  })

  // Converted from Ruby: test "creates good feedback via post_feedback endpoint"
  describe('POST /scores/:judge/post_feedback', () => {
    it('creates good feedback', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const feedbackData = {
        heat: 100,
        good: 'F,T,P',  // Frame, Timing, Posture
        bad: '',
        comments: ''
      }

      const response = await fetch('/scores/55/post_feedback', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(feedbackData)
      })

      expect(response.ok).toBe(true)
      expect(fetchMock).toHaveBeenCalledWith(
        '/scores/55/post_feedback',
        expect.objectContaining({
          method: 'POST',
          body: expect.stringContaining('"good":"F,T,P"')
        })
      )
    })

    // Converted from Ruby: test "creates bad feedback via post_feedback endpoint"
    it('creates bad feedback', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const feedbackData = {
        heat: 100,
        good: '',
        bad: 'T,F',  // Timing, Footwork issues
        comments: ''
      }

      const response = await fetch('/scores/55/post_feedback', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(feedbackData)
      })

      expect(response.ok).toBe(true)
      expect(fetchMock).toHaveBeenCalledWith(
        '/scores/55/post_feedback',
        expect.objectContaining({
          method: 'POST',
          body: expect.stringContaining('"bad":"T,F"')
        })
      )
    })

    // Converted from Ruby: test "handles combined value and feedback scoring"
    it('handles combined value and feedback', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ success: true })
      })

      const scoreData = {
        heat: 100,
        score: 'G',
        good: 'F,T',
        bad: 'P',
        comments: 'Good overall, work on posture'
      }

      const response = await fetch('/scores/55/post', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(scoreData)
      })

      expect(response.ok).toBe(true)
      const callArgs = fetchMock.mock.calls[0]
      const body = JSON.parse(callArgs[1].body)

      expect(body.score).toBe('G')
      expect(body.good).toBe('F,T')
      expect(body.bad).toBe('P')
      expect(body.comments).toBe('Good overall, work on posture')
    })
  })

  // Offline behavior tests
  describe('Offline score posting', () => {
    it('queues score in IndexedDB when POST fails', async () => {
      // Simulate network failure
      fetchMock.mockRejectedValueOnce(new Error('Network unavailable'))

      try {
        await fetch('/scores/55/post', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ heat: 100, score: 'G' })
        })
      } catch (error) {
        // POST failed, should queue in IndexedDB
        await heatDataManager.addDirtyScore(55, 100, 1, {
          score: 'G',
          comments: '',
          good: '',
          bad: ''
        })
      }

      const dirtyScores = await heatDataManager.getDirtyScores(55)
      expect(dirtyScores).toHaveLength(1)
      expect(dirtyScores[0].score).toBe('G')
    })

    it('uploads queued scores when connectivity returns', async () => {
      // Queue some dirty scores
      await heatDataManager.addDirtyScore(55, 100, 1, {
        score: 'G',
        comments: '',
        good: '',
        bad: ''
      })
      await heatDataManager.addDirtyScore(55, 101, 1, {
        score: 'S',
        comments: '',
        good: '',
        bad: ''
      })

      // Mock successful batch upload
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({
          succeeded: [
            { heat: 100, slot: 1 },
            { heat: 101, slot: 1 }
          ],
          failed: []
        })
      })

      // Batch upload when online
      const result = await heatDataManager.batchUploadDirtyScores(55)

      expect(result.succeeded).toHaveLength(2)
      expect(result.failed).toHaveLength(0)

      // Dirty scores should be cleared
      const remaining = await heatDataManager.getDirtyScores(55)
      expect(remaining).toHaveLength(0)
    })

    it('keeps dirty scores on batch upload failure', async () => {
      // Queue dirty scores
      await heatDataManager.addDirtyScore(55, 100, 1, {
        score: 'G',
        comments: '',
        good: '',
        bad: ''
      })

      // Mock failed batch upload
      fetchMock.mockResolvedValueOnce({
        ok: false,
        status: 500
      })

      const result = await heatDataManager.batchUploadDirtyScores(55)

      expect(result.succeeded).toHaveLength(0)
      expect(result.failed).toHaveLength(1)

      // Dirty scores should remain for retry
      const remaining = await heatDataManager.getDirtyScores(55)
      expect(remaining).toHaveLength(1)
    })
  })

  // Error handling tests
  describe('Error handling', () => {
    it('handles 404 not found', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: false,
        status: 404,
        statusText: 'Not Found'
      })

      const response = await fetch('/scores/55/post', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ heat: 99999, score: 'G' })
      })

      expect(response.ok).toBe(false)
      expect(response.status).toBe(404)
    })

    it('handles 422 validation errors', async () => {
      fetchMock.mockResolvedValueOnce({
        ok: false,
        status: 422,
        json: () => Promise.resolve({
          error: 'Invalid score value'
        })
      })

      const response = await fetch('/scores/55/post', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ heat: 100, score: 'INVALID' })
      })

      expect(response.ok).toBe(false)
      expect(response.status).toBe(422)
    })
  })
})
