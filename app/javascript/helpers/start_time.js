/**
 * Start time parsing for agenda items.
 *
 * Mirrors app/models/concerns/start_time.rb so the category form can show how
 * a typed time will be saved before it is submitted.  The server remains the
 * authority; keep the two parsers (and their tests) in step.
 */

// Digits, optionally followed by up to two letters (an attempt at am/pm).
const TIME_LIKE = /^\d[\d:.\s]*(?:[a-z]\.?\s*){0,2}$/i

// Without am/pm, hours up to this one are assumed to be in the afternoon.
const LAST_ASSUMED_PM_HOUR = 6

// Returns "HH:MM" (24-hour) for recognizable input, null otherwise.
export function parseStartTime(value) {
  const text = String(value ?? "").trim().toLowerCase()
  if (!text) return null
  if (/^(12(:00)?\s*)?noon$/.test(text)) return "12:00"
  if (/^(12(:00)?\s*)?midnight$/.test(text)) return "00:00"

  const match = text.match(/^(\d{1,2})(?:[:.]?(\d{2}))?\s*(?:([ap])(?:\.?\s*m)?\.?)?$/)
  if (!match) return null

  let hour = Number(match[1])
  const minute = Number(match[2] ?? 0)
  const meridian = match[3]
  if (minute > 59) return null

  if (meridian) {
    if (hour < 1 || hour > 12) return null
    if (hour === 12) hour = 0
    if (meridian === "p") hour += 12
  } else {
    if (hour > 23) return null
    if (hour >= 1 && hour <= LAST_ASSUMED_PM_HOUR && !match[1].startsWith("0")) hour += 12
  }

  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`
}

// True for input that is evidently meant to be a time of day, as opposed to
// free text such as "TBD" or "after lunch".
export function isTimeLike(value) {
  return TIME_LIKE.test(String(value ?? "").trim())
}

// Friendly display form: "13:00" -> "1:00 PM".  Free text is returned unchanged.
export function displayStartTime(value) {
  const canonical = parseStartTime(value)
  if (!canonical) return String(value ?? "")

  const [hour, minute] = canonical.split(":").map(Number)
  return `${hour % 12 || 12}:${String(minute).padStart(2, "0")} ${hour < 12 ? "AM" : "PM"}`
}

// What the form should tell the user about what they have typed:
// {error: message or "", hint: preview of the saved time or ""}
export function checkStartTime(value) {
  const raw = String(value ?? "").trim()
  const parsed = parseStartTime(raw)

  if (parsed) return { error: "", hint: `→ ${displayStartTime(parsed)}` }
  if (raw && isTimeLike(raw)) {
    return { error: `"${raw}" isn't a time we recognize. Try something like 8:30 am or 1 pm`, hint: "" }
  }
  return { error: "", hint: "" }
}
