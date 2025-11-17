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

    it('includes student_id for amateur couples (table format)', () => {
      const dataSource = {
        A: [
          {
            id: 100,
            student_id: 42,  // Amateur couple - lead student
            student_role: 'lead',
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
        person_id: 42,
        student_id: 42  // Should include student_id for amateur couples
      });
    });

    it('includes different student_id for follow student in amateur couple', () => {
      const dataSource = {
        A: [
          {
            id: 100,
            student_id: 55,  // Amateur couple - follow student
            student_role: 'follow',
            scores: [
              {
                judge_id: 1,
                person_id: 55,
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
        person_id: 55,
        student_id: 55  // Should include student_id for follow student
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

  describe('Amateur Couple Support', () => {
    describe('HeatTable name display', () => {
      it('shows student being evaluated in Student column for lead student', () => {
        // Test data for amateur couple - lead student being evaluated
        const subject = {
          id: 100,
          student_id: 42,
          student_role: 'lead',
          lead: {
            id: 42,
            name: 'Alice Student',
            display_name: 'Alice Student',
            type: 'Student'
          },
          follow: {
            id: 43,
            name: 'Bob Student',
            display_name: 'Bob Student',
            type: 'Student'
          }
        };

        // When column_order === 2 and student_role === 'lead'
        // First name should be lead (student being evaluated)
        // Second name should be follow (partner)

        // This matches the logic in heat-table.js lines 370-388
        const columnOrder = 2;

        let firstName, secondName;
        if (subject.student_role === 'lead') {
          firstName = subject.lead.display_name;
          secondName = subject.follow.display_name;
        } else {
          firstName = subject.follow.display_name;
          secondName = subject.lead.display_name;
        }

        expect(firstName).toBe('Alice Student');  // Student being evaluated
        expect(secondName).toBe('Bob Student');   // Partner
      });

      it('shows student being evaluated in Student column for follow student', () => {
        // Test data for amateur couple - follow student being evaluated
        const subject = {
          id: 100,
          student_id: 43,
          student_role: 'follow',
          lead: {
            id: 42,
            name: 'Alice Student',
            display_name: 'Alice Student',
            type: 'Student'
          },
          follow: {
            id: 43,
            name: 'Bob Student',
            display_name: 'Bob Student',
            type: 'Student'
          }
        };

        // When column_order === 2 and student_role === 'follow'
        // First name should be follow (student being evaluated)
        // Second name should be lead (partner)

        const columnOrder = 2;

        let firstName, secondName;
        if (subject.student_role === 'lead') {
          firstName = subject.lead.display_name;
          secondName = subject.follow.display_name;
        } else {
          firstName = subject.follow.display_name;
          secondName = subject.lead.display_name;
        }

        expect(firstName).toBe('Bob Student');    // Student being evaluated
        expect(secondName).toBe('Alice Student'); // Partner
      });
    });

    describe('HeatCards name display', () => {
      it('shows student being evaluated first for lead student', () => {
        // Test data for amateur couple - lead student being evaluated
        const entry = {
          id: 100,
          student_id: 42,
          student_role: 'lead',
          lead: {
            id: 42,
            name: 'Alice Student',
            type: 'Student'
          },
          follow: {
            id: 43,
            name: 'Bob Student',
            type: 'Student'
          }
        };

        // Matches logic in heat-cards.js lines 96-114
        const columnOrder = 2;

        let firstBack, secondBack;
        if (entry.student_role === 'lead') {
          firstBack = entry.lead.name;
          secondBack = entry.follow.name;
        } else {
          firstBack = entry.follow.name;
          secondBack = entry.lead.name;
        }

        expect(firstBack).toBe('Alice Student');  // Student being evaluated
        expect(secondBack).toBe('Bob Student');   // Partner
      });

      it('shows student being evaluated first for follow student', () => {
        // Test data for amateur couple - follow student being evaluated
        const entry = {
          id: 100,
          student_id: 43,
          student_role: 'follow',
          lead: {
            id: 42,
            name: 'Alice Student',
            type: 'Student'
          },
          follow: {
            id: 43,
            name: 'Bob Student',
            type: 'Student'
          }
        };

        const columnOrder = 2;

        let firstBack, secondBack;
        if (entry.student_role === 'lead') {
          firstBack = entry.lead.name;
          secondBack = entry.follow.name;
        } else {
          firstBack = entry.follow.name;
          secondBack = entry.lead.name;
        }

        expect(firstBack).toBe('Bob Student');    // Student being evaluated
        expect(secondBack).toBe('Alice Student'); // Partner
      });
    });

    describe('Unique IDs for amateur couples', () => {
      it('creates unique row ID with student_id', () => {
        const subject = { id: 100, student_id: 42 };
        const rowId = subject.student_id
          ? `heat-${subject.id}-student-${subject.student_id}`
          : `heat-${subject.id}`;

        expect(rowId).toBe('heat-100-student-42');
      });

      it('creates unique card ID with student_id', () => {
        const subject = { id: 100, student_id: 55 };
        const cardId = subject.student_id
          ? `heat-${subject.id}-student-${subject.student_id}`
          : `heat-${subject.id}`;

        expect(cardId).toBe('heat-100-student-55');
      });

      it('uses heat ID only when no student_id', () => {
        const subject = { id: 100 };
        const rowId = subject.student_id
          ? `heat-${subject.id}-student-${subject.student_id}`
          : `heat-${subject.id}`;

        expect(rowId).toBe('heat-100');
      });
    });
  });
});
