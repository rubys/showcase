import { describe, it, expect } from 'vitest'
import { parseStartTime, isTimeLike, displayStartTime, checkStartTime } from '../../app/javascript/helpers/start_time'

/**
 * Start Time Tests
 *
 * The category form previews how a typed start time will be saved.  These
 * cases mirror test/models/concerns/start_time_test.rb so the JavaScript
 * parser stays in step with the Rails one.
 */

describe('Start time parsing', () => {
  it('parses common ways of typing a time', () => {
    const cases = {
      '8:30 am': '08:30',
      '8:30am': '08:30',
      '8:30 AM': '08:30',
      '8:30 a.m.': '08:30',
      '10 a.m.': '10:00',
      '1 pm': '13:00',
      '1p': '13:00',
      '1:15 P.M.': '13:15',
      '830 pm': '20:30',
      '12 pm': '12:00',
      '12:30 am': '00:30',
      'noon': '12:00',
      'midnight': '00:00',
      '13:00': '13:00',
      '08:30': '08:30',
      '1300': '13:00',
      '8.30': '08:30',
      '  9:05 pm ': '21:05'
    }

    for (const [input, expected] of Object.entries(cases)) {
      expect(parseStartTime(input), `parsing "${input}"`).toBe(expected)
    }
  })

  it('reads early hours without am/pm as afternoon', () => {
    const cases = {
      '1:30': '13:30',
      '2': '14:00',
      '130': '13:30',
      '6:00': '18:00',
      '7:00': '07:00',
      '8:30': '08:30',
      '11': '11:00',
      '12:15': '12:15',
      '19:00': '19:00'
    }

    for (const [input, expected] of Object.entries(cases)) {
      expect(parseStartTime(input), `parsing "${input}"`).toBe(expected)
    }
  })

  it('treats a leading zero as 24-hour time', () => {
    expect(parseStartTime('01:30')).toBe('01:30')
    expect(parseStartTime('0130')).toBe('01:30')
    expect(parseStartTime('00:15')).toBe('00:15')
    expect(parseStartTime('1:30 am')).toBe('01:30')
  })

  it('leaves canonical times unchanged', () => {
    for (const time of ['00:00', '01:30', '06:00', '08:30', '12:00', '13:30', '23:59']) {
      expect(parseStartTime(time)).toBe(time)
    }
  })

  it('rejects things that are not times', () => {
    for (const input of ['', null, undefined, 'after lunch', 'TBD', '9am Sunday', '25:00', '8:75', '13 pm', '0 am', '8:30 xm', 2500]) {
      expect(parseStartTime(input), `parsing ${JSON.stringify(input)}`).toBeNull()
    }
  })
})

describe('Telling times from free text', () => {
  it('recognizes attempts at a time', () => {
    for (const input of ['25:00', '8:75', '13 pm', '0 am', '8:30 xm', '2500', 2500, '99:99', '8:30 pm']) {
      expect(isTimeLike(input), `"${input}"`).toBe(true)
    }
  })

  it('leaves free text alone', () => {
    for (const input of ['', null, 'after lunch', 'TBD', '9am Sunday', 'noon-ish']) {
      expect(isTimeLike(input), `"${input}"`).toBe(false)
    }
  })
})

describe('Start time display', () => {
  it('displays times in 12-hour form', () => {
    expect(displayStartTime('08:30')).toBe('8:30 AM')
    expect(displayStartTime('13:00')).toBe('1:00 PM')
    expect(displayStartTime('12:00')).toBe('12:00 PM')
    expect(displayStartTime('00:15')).toBe('12:15 AM')
    expect(displayStartTime('10 a.m.')).toBe('10:00 AM')
    expect(displayStartTime(null)).toBe('')
    expect(displayStartTime('after lunch')).toBe('after lunch')
  })
})

describe('Start time form feedback', () => {
  it('previews how a time will be saved', () => {
    expect(checkStartTime('8:30 am')).toEqual({ error: '', hint: '→ 8:30 AM' })
    expect(checkStartTime('1:30')).toEqual({ error: '', hint: '→ 1:30 PM' })
    expect(checkStartTime('01:30')).toEqual({ error: '', hint: '→ 1:30 AM' })
  })

  it('says nothing about a blank field or free text', () => {
    expect(checkStartTime('')).toEqual({ error: '', hint: '' })
    expect(checkStartTime('   ')).toEqual({ error: '', hint: '' })
    expect(checkStartTime('TBD')).toEqual({ error: '', hint: '' })
    expect(checkStartTime('9am Sunday')).toEqual({ error: '', hint: '' })
  })

  it('blocks something that looks like a time but is not one', () => {
    const { error, hint } = checkStartTime('25:00')
    expect(error).toBe('"25:00" isn\'t a time we recognize. Try something like 8:30 am or 1 pm')
    expect(hint).toBe('')
    expect(checkStartTime('8:75 pm').error).not.toBe('')
  })
})
