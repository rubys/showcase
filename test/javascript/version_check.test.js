import { describe, it, expect, beforeEach, vi } from 'vitest'
import { JSDOM } from 'jsdom'

/**
 * Version Check Tests
 *
 * These tests verify that the SPA correctly checks server version before
 * refetching data, implementing the strategy from plans/SPA_SYNC_STRATEGY.md:
 * - Lightweight version check on navigation
 * - Conditional refetch only when data changes
 * - Offline fallback to cached data
 */

describe('Version Check', () => {
  let dom
  let window
  let document
  let HeatPage

  beforeEach(async () => {
    // Create a fresh DOM for each test
    dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
      url: 'http://localhost:3000/scores/40/spa?style=radio'
    })
    window = dom.window
    document = window.document

    // Mock globals
    global.window = window
    global.document = document
    global.CustomEvent = window.CustomEvent
    global.fetch = vi.fn()

    // Mock inject_region helper
    window.inject_region = (headers) => headers

    // Import HeatPage after mocking globals
    const module = await import('../../app/javascript/components/heat-page.js')
    HeatPage = module.HeatPage
  })

  describe('Version Comparison Logic', () => {
    it('returns true when versions match exactly', () => {
      const heatPage = new HeatPage()

      const cachedVersion = {
        max_updated_at: '2025-11-06T15:30:00.123Z',
        heat_count: 142
      }

      const serverVersion = {
        max_updated_at: '2025-11-06T15:30:00.123Z',
        heat_count: 142
      }

      expect(heatPage.isVersionCurrent(cachedVersion, serverVersion)).toBe(true)
    })

    it('returns false when max_updated_at differs', () => {
      const heatPage = new HeatPage()

      const cachedVersion = {
        max_updated_at: '2025-11-06T15:00:00.123Z',
        heat_count: 142
      }

      const serverVersion = {
        max_updated_at: '2025-11-06T15:30:00.123Z',
        heat_count: 142
      }

      expect(heatPage.isVersionCurrent(cachedVersion, serverVersion)).toBe(false)
    })

    it('returns false when heat_count differs', () => {
      const heatPage = new HeatPage()

      const cachedVersion = {
        max_updated_at: '2025-11-06T15:30:00.123Z',
        heat_count: 142
      }

      const serverVersion = {
        max_updated_at: '2025-11-06T15:30:00.123Z',
        heat_count: 143
      }

      expect(heatPage.isVersionCurrent(cachedVersion, serverVersion)).toBe(false)
    })

    it('returns false when cached version is null', () => {
      const heatPage = new HeatPage()

      const serverVersion = {
        max_updated_at: '2025-11-06T15:30:00.123Z',
        heat_count: 142
      }

      expect(heatPage.isVersionCurrent(null, serverVersion)).toBe(false)
    })

    it('returns false when server version is null', () => {
      const heatPage = new HeatPage()

      const cachedVersion = {
        max_updated_at: '2025-11-06T15:30:00.123Z',
        heat_count: 142
      }

      expect(heatPage.isVersionCurrent(cachedVersion, null)).toBe(false)
    })
  })

  describe('Version Check Endpoint Integration', () => {
    it('builds correct version check URL with base-path', async () => {
      const heatPage = new HeatPage()
      heatPage.currentHeatNumber = 5
      heatPage.basePath = '/showcase/2025/city/event'
      heatPage.judgeId = 40

      // Mock heatDataManager
      const mockGetCachedVersion = vi.fn(() => ({
        max_updated_at: '2025-11-06T15:30:00.123Z',
        heat_count: 142
      }))

      // Mock version check endpoint response - version matches
      global.fetch = vi.fn((url) => {
        expect(url).toBe('/showcase/2025/city/event/scores/40/version/5')
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({
            heat_number: 5,
            max_updated_at: '2025-11-06T15:30:00.123Z',
            heat_count: 142
          })
        })
      })

      // Import heatDataManager and mock it
      const { heatDataManager } = await import('../../app/javascript/helpers/heat_data_manager.js')
      heatDataManager.getCachedVersion = mockGetCachedVersion

      await heatPage.checkVersionAndRefetch()

      // Verify fetch was called with correct URL
      expect(global.fetch).toHaveBeenCalledWith('/showcase/2025/city/event/scores/40/version/5')
    })

    it('uses cached data when version check fails (offline)', async () => {
      const heatPage = new HeatPage()
      heatPage.currentHeatNumber = 5
      heatPage.basePath = ''
      heatPage.judgeId = 40

      // Mock failed version check (offline)
      global.fetch = vi.fn(() => Promise.resolve({
        ok: false,
        status: 503
      }))

      // Should not throw, should fall back to cached data
      await expect(heatPage.checkVersionAndRefetch()).resolves.toBeUndefined()
    })

    it('uses cached data when network error occurs', async () => {
      const heatPage = new HeatPage()
      heatPage.currentHeatNumber = 5
      heatPage.basePath = ''
      heatPage.judgeId = 40

      // Mock network error
      global.fetch = vi.fn(() => Promise.reject(new Error('Network unavailable')))

      // Should not throw, should fall back to cached data
      await expect(heatPage.checkVersionAndRefetch()).resolves.toBeUndefined()
    })

    it('refetches data when version differs', async () => {
      const heatPage = new HeatPage()
      heatPage.currentHeatNumber = 5
      heatPage.basePath = ''
      heatPage.judgeId = 40

      // Mock heatDataManager
      const mockGetCachedVersion = vi.fn(() => ({
        max_updated_at: '2025-11-06T15:00:00.123Z',
        heat_count: 142
      }))

      const mockGetData = vi.fn(() => Promise.resolve({
        heats: [],
        judge: {},
        event: {}
      }))

      // Import and mock heatDataManager
      const { heatDataManager } = await import('../../app/javascript/helpers/heat_data_manager.js')
      heatDataManager.getCachedVersion = mockGetCachedVersion
      heatDataManager.getData = mockGetData

      // Mock version check endpoint - version changed
      global.fetch = vi.fn(() => Promise.resolve({
        ok: true,
        json: () => Promise.resolve({
          heat_number: 5,
          max_updated_at: '2025-11-06T15:30:00.123Z', // Different!
          heat_count: 142
        })
      }))

      await heatPage.checkVersionAndRefetch()

      // Verify getData was called with force refetch
      expect(mockGetData).toHaveBeenCalledWith(40, true)
    })

    it('skips refetch when version matches', async () => {
      const heatPage = new HeatPage()
      heatPage.currentHeatNumber = 5
      heatPage.basePath = ''
      heatPage.judgeId = 40

      // Mock heatDataManager
      const mockGetCachedVersion = vi.fn(() => ({
        max_updated_at: '2025-11-06T15:30:00.123Z',
        heat_count: 142
      }))

      const mockGetData = vi.fn()

      // Import and mock heatDataManager
      const { heatDataManager } = await import('../../app/javascript/helpers/heat_data_manager.js')
      heatDataManager.getCachedVersion = mockGetCachedVersion
      heatDataManager.getData = mockGetData

      // Mock version check endpoint - version matches
      global.fetch = vi.fn(() => Promise.resolve({
        ok: true,
        json: () => Promise.resolve({
          heat_number: 5,
          max_updated_at: '2025-11-06T15:30:00.123Z', // Same!
          heat_count: 142 // Same!
        })
      }))

      await heatPage.checkVersionAndRefetch()

      // Verify getData was NOT called
      expect(mockGetData).not.toHaveBeenCalled()
    })
  })

  describe('Version Check on Navigation', () => {
    it('calls checkVersionAndRefetch when navigating to heat', async () => {
      const heatPage = new HeatPage()
      heatPage.judgeId = 40
      heatPage.scoringStyle = 'radio'
      heatPage.basePath = ''
      heatPage.data = { heats: [], judge: {}, event: {} }

      // Import HeatNavigator and initialize it
      const { default: HeatNavigator } = await import('../../app/javascript/helpers/heat_navigator.js')
      heatPage.navigator = new HeatNavigator(heatPage)

      // Mock checkVersionAndRefetch
      const mockCheck = vi.fn(() => Promise.resolve())
      heatPage.checkVersionAndRefetch = mockCheck

      // Mock render to avoid DOM manipulation
      heatPage.render = vi.fn()

      await heatPage.navigator.navigateToHeat(5, 0)

      // Verify version check was called
      expect(mockCheck).toHaveBeenCalled()
    })
  })
})
