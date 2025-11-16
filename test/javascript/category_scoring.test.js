/**
 * Category Scoring Tests
 *
 * Tests that heat components correctly include person_id when category scoring
 * is enabled. Category scoring allows students to receive a single consolidated
 * score per category (rather than per-heat scoring).
 */

import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { heatDataManager } from '../../app/javascript/helpers/heat_data_manager.js';
import { enhanceWithPersonId } from '../../app/javascript/helpers/score_data_helper.js';

// Import components
import { HeatRank } from '../../app/javascript/components/heat-types/heat-rank.js';

describe('Category Scoring Integration', () => {
  let saveScoreSpy;

  beforeEach(() => {
    // Spy on heatDataManager.saveScore to capture calls
    saveScoreSpy = vi.spyOn(heatDataManager, 'saveScore').mockResolvedValue({});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('enhanceWithPersonId helper', () => {
    it('includes person_id when category scoring enabled (table format)', () => {
      const dataSource = {
        A: [
          {
            id: 100,
            scores: [
              {
                judge_id: 1,
                person_id: 42,
                category_scoring: true
              }
            ]
          }
        ]
      };

      const data = { heat: 100, score: '3' };
      enhanceWithPersonId(data, dataSource, 100, 1);

      expect(data).toEqual({
        heat: 100,
        score: '3',
        person_id: 42
      });
    });

    it('does not include person_id when category scoring disabled (table format)', () => {
      const dataSource = {
        A: [
          {
            id: 100,
            scores: [
              {
                judge_id: 1,
                value: '2'  // No person_id
              }
            ]
          }
        ]
      };

      const data = { heat: 100, score: '3' };
      enhanceWithPersonId(data, dataSource, 100, 1);

      expect(data).toEqual({
        heat: 100,
        score: '3'
        // No person_id
      });
    });

    it('includes person_id when category scoring enabled (solo format)', () => {
      const dataSource = {
        subjects: [
          {
            id: 100,
            scores: [
              {
                judge_id: 1,
                person_id: 42,
                category_scoring: true
              }
            ]
          }
        ]
      };

      const data = { heat: 100, score: '92' };
      enhanceWithPersonId(data, dataSource, 100, 1);

      expect(data.person_id).toBe(42);
    });

    it('includes person_id when category scoring enabled (cards format)', () => {
      const dataSource = {
        '': [
          {
            id: 100,
            scores: [
              {
                judge_id: 1,
                person_id: 42,
                category_scoring: true
              }
            ]
          }
        ]
      };

      const data = { heat: 100, score: '2' };
      enhanceWithPersonId(data, dataSource, 100, 1);

      expect(data.person_id).toBe(42);
    });
  });

  describe('HeatRank', () => {
    it('includes person_id when category scoring enabled', async () => {
      const rank = document.createElement('heat-rank');
      rank.setAttribute('heat-data', JSON.stringify({
        number: 1,
        dance: { name: 'Waltz', uses_scrutineering: true },
        subjects: [
          {
            id: 100,
            lead: { id: 1, name: 'Student A', type: 'Student', back: '1' },
            follow: { id: 2, name: 'Instructor A', type: 'Professional' },
            age: { category: 'Adult' },
            level: { initials: 'NC' },
            scores: [
              {
                judge_id: 1,
                person_id: 1,  // Category scoring enabled
                category_scoring: true,
                value: '1'
              }
            ]
          },
          {
            id: 101,
            lead: { id: 3, name: 'Student B', type: 'Student', back: '2' },
            follow: { id: 4, name: 'Instructor B', type: 'Professional' },
            age: { category: 'Adult' },
            level: { initials: 'NC' },
            scores: [
              {
                judge_id: 1,
                person_id: 3,  // Category scoring enabled
                category_scoring: true,
                value: '2'
              }
            ]
          }
        ]
      }));
      rank.setAttribute('event-data', JSON.stringify({}));
      rank.setAttribute('judge-data', JSON.stringify({ id: 1 }));
      rank.setAttribute('slot', '1');
      document.body.appendChild(rank);

      // Save ranking
      await rank.saveRanking();

      expect(saveScoreSpy).toHaveBeenCalledWith(1, expect.objectContaining({
        heat: 100,
        slot: 1,
        score: '1',
        person_id: 1  // Should include person_id for first subject
      }));

      expect(saveScoreSpy).toHaveBeenCalledWith(1, expect.objectContaining({
        heat: 101,
        slot: 1,
        score: '2',
        person_id: 3  // Should include person_id for second subject
      }));

      document.body.removeChild(rank);
    });

    it('does not include person_id when category scoring disabled', async () => {
      const rank = document.createElement('heat-rank');
      rank.setAttribute('heat-data', JSON.stringify({
        number: 1,
        dance: { name: 'Waltz', uses_scrutineering: true },
        subjects: [
          {
            id: 100,
            lead: { id: 1, name: 'Student A', type: 'Student', back: '1' },
            follow: { id: 2, name: 'Instructor A', type: 'Professional' },
            age: { category: 'Adult' },
            level: { initials: 'NC' },
            scores: [
              {
                judge_id: 1,
                value: '1'  // No person_id (per-heat scoring)
              }
            ]
          }
        ]
      }));
      rank.setAttribute('event-data', JSON.stringify({}));
      rank.setAttribute('judge-data', JSON.stringify({ id: 1 }));
      rank.setAttribute('slot', '1');
      document.body.appendChild(rank);

      // Save ranking
      await rank.saveRanking();

      expect(saveScoreSpy).toHaveBeenCalledWith(1, {
        heat: 100,
        slot: 1,
        score: '1'
        // Should NOT include person_id
      });

      document.body.removeChild(rank);
    });
  });
});
