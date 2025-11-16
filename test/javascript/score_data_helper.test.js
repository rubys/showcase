import { describe, it, expect } from 'vitest';
import { findSubject, getSubjectScore, enhanceWithPersonId } from '../../app/javascript/helpers/score_data_helper.js';

describe('ScoreDataHelper', () => {
  describe('findSubject', () => {
    it('finds subject in direct subjects array (solo/rank format)', () => {
      const data = {
        subjects: [
          { id: 100, name: 'First' },
          { id: 101, name: 'Second' },
          { id: 102, name: 'Third' }
        ]
      };

      const subject = findSubject(data, 101);
      expect(subject).toEqual({ id: 101, name: 'Second' });
    });

    it('finds subject in ballrooms object (table format)', () => {
      const data = {
        A: [
          { id: 100, name: 'First' },
          { id: 101, name: 'Second' }
        ],
        B: [
          { id: 102, name: 'Third' },
          { id: 103, name: 'Fourth' }
        ]
      };

      const subject = findSubject(data, 103);
      expect(subject).toEqual({ id: 103, name: 'Fourth' });
    });

    it('finds subject in results object (cards format)', () => {
      const data = {
        '1': [{ id: 100, name: 'First' }],
        '2': [{ id: 101, name: 'Second' }],
        '': [{ id: 102, name: 'Unscored' }]
      };

      const subject = findSubject(data, 102);
      expect(subject).toEqual({ id: 102, name: 'Unscored' });
    });

    it('returns null when subject not found', () => {
      const data = {
        subjects: [
          { id: 100, name: 'First' },
          { id: 101, name: 'Second' }
        ]
      };

      const subject = findSubject(data, 999);
      expect(subject).toBeNull();
    });

    it('returns null for empty data', () => {
      expect(findSubject({ subjects: [] }, 100)).toBeNull();
      expect(findSubject({}, 100)).toBeNull();
    });

    it('returns null for null/undefined data', () => {
      expect(findSubject(null, 100)).toBeNull();
      expect(findSubject(undefined, 100)).toBeNull();
    });
  });

  describe('getSubjectScore', () => {
    it('returns score for matching judge', () => {
      const subject = {
        scores: [
          { judge_id: 1, value: '1' },
          { judge_id: 2, value: '2' },
          { judge_id: 3, value: '3' }
        ]
      };

      const score = getSubjectScore(subject, 2);
      expect(score).toEqual({ judge_id: 2, value: '2' });
    });

    it('returns null when judge not found', () => {
      const subject = {
        scores: [
          { judge_id: 1, value: '1' }
        ]
      };

      const score = getSubjectScore(subject, 999);
      expect(score).toBeNull();
    });

    it('returns null when subject has no scores', () => {
      const subject = { id: 100 };
      expect(getSubjectScore(subject, 1)).toBeNull();
    });

    it('returns null when subject is null/undefined', () => {
      expect(getSubjectScore(null, 1)).toBeNull();
      expect(getSubjectScore(undefined, 1)).toBeNull();
    });
  });

  describe('enhanceWithPersonId', () => {
    it('adds person_id from category score', () => {
      const dataSource = {
        subjects: [
          {
            id: 100,
            scores: [
              {
                judge_id: 1,
                person_id: 42,
                category_scoring: true,
                value: 'GH'
              }
            ]
          }
        ]
      };

      const data = { heat: 100, score: 'GH' };
      enhanceWithPersonId(data, dataSource, 100, 1);

      expect(data).toEqual({
        heat: 100,
        score: 'GH',
        person_id: 42
      });
    });

    it('does not add person_id when not present in score', () => {
      const dataSource = {
        subjects: [
          {
            id: 100,
            scores: [
              {
                judge_id: 1,
                value: '1'
              }
            ]
          }
        ]
      };

      const data = { heat: 100, score: '1' };
      enhanceWithPersonId(data, dataSource, 100, 1);

      expect(data).toEqual({
        heat: 100,
        score: '1'
      });
      expect(data.person_id).toBeUndefined();
    });

    it('does not add person_id when subject not found', () => {
      const dataSource = {
        subjects: [
          { id: 100, scores: [] }
        ]
      };

      const data = { heat: 999, score: '1' };
      enhanceWithPersonId(data, dataSource, 999, 1);

      expect(data).toEqual({
        heat: 999,
        score: '1'
      });
      expect(data.person_id).toBeUndefined();
    });

    it('does not add person_id when score for judge not found', () => {
      const dataSource = {
        subjects: [
          {
            id: 100,
            scores: [
              { judge_id: 2, person_id: 42 }
            ]
          }
        ]
      };

      const data = { heat: 100, score: '1' };
      enhanceWithPersonId(data, dataSource, 100, 1);

      expect(data).toEqual({
        heat: 100,
        score: '1'
      });
      expect(data.person_id).toBeUndefined();
    });

    it('works with ballrooms object (table format)', () => {
      const dataSource = {
        A: [
          {
            id: 100,
            scores: [
              { judge_id: 1, person_id: 42 }
            ]
          }
        ],
        B: [
          {
            id: 101,
            scores: [
              { judge_id: 1, person_id: 43 }
            ]
          }
        ]
      };

      const data = { heat: 101, score: '2' };
      enhanceWithPersonId(data, dataSource, 101, 1);

      expect(data.person_id).toBe(43);
    });

    it('works with results object (cards format)', () => {
      const dataSource = {
        '1': [
          {
            id: 100,
            scores: [
              { judge_id: 1, person_id: 42 }
            ]
          }
        ],
        '': [
          {
            id: 101,
            scores: [
              { judge_id: 1, person_id: 43 }
            ]
          }
        ]
      };

      const data = { heat: 101, score: '2' };
      enhanceWithPersonId(data, dataSource, 101, 1);

      expect(data.person_id).toBe(43);
    });

    it('returns the same data object (mutates in place)', () => {
      const dataSource = {
        subjects: [
          {
            id: 100,
            scores: [
              { judge_id: 1, person_id: 42 }
            ]
          }
        ]
      };

      const data = { heat: 100, score: '1' };
      const result = enhanceWithPersonId(data, dataSource, 100, 1);

      expect(result).toBe(data); // Same object reference
      expect(data.person_id).toBe(42);
    });

    it('preserves existing data fields', () => {
      const dataSource = {
        subjects: [
          {
            id: 100,
            scores: [
              { judge_id: 1, person_id: 42 }
            ]
          }
        ]
      };

      const data = { heat: 100, score: '1', comments: 'Great job!', slot: 2 };
      enhanceWithPersonId(data, dataSource, 100, 1);

      expect(data).toEqual({
        heat: 100,
        score: '1',
        comments: 'Great job!',
        slot: 2,
        person_id: 42
      });
    });
  });
});
