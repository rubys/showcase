# Start times for agenda items (categories and category extensions).
#
# Times are entered in a plain text field so they work the same in every
# browser (Safari-based browsers such as DuckDuckGo render <input type="time">
# as a segmented control that silently rejects typed text like "8:30 am").
#
# Anything recognizable as a time is normalized to 24-hour "HH:MM", which is
# the form the scheduler (Printable#generate_agenda) handles most directly.
# Free text ("TBD", "after lunch", "9am Sunday") is kept as typed, as it
# always has been.  Only input that looks like a time but isn't one ("25:00",
# "8:75 pm") is rejected, rather than being saved and then ignored when start
# times are computed.
#
# app/javascript/helpers/start_time.js mirrors this parser for live feedback
# in the category form; keep the two (and their tests) in step.
module StartTime
  extend ActiveSupport::Concern

  # Digits, optionally followed by up to two letters (an attempt at am/pm).
  TIME_LIKE = /\A\d[\d:.\s]*(?:[a-z]\.?\s*){0,2}\z/i

  # Without am/pm, hours up to this one are assumed to be in the afternoon:
  # nobody starts an agenda item at 1:30 in the morning.
  LAST_ASSUMED_PM_HOUR = 6

  included do
    normalizes :time, with: ->(value) { StartTime.parse(value) || value.to_s.strip }
    validate :start_time_recognized, if: :time_changed?
  end

  # Returns "HH:MM" (24-hour) for recognizable input, nil otherwise.
  #
  # Accepts: "8:30 am", "8:30am", "8:30 a.m.", "8 pm", "8p", "830 pm",
  # "13:00", "1300", "8.30", "noon", "12 noon", "midnight".
  #
  # Without am/pm, hours 1 through 6 are read as afternoon ("1:30" is 1:30 PM,
  # "8:30" is 8:30 AM).  A leading zero means 24-hour time ("01:30" is
  # 1:30 AM), so values already in canonical form parse to themselves.
  def self.parse(value)
    text = value.to_s.strip.downcase
    return nil if text.empty?
    return "12:00" if text.match?(/\A(12(:00)?\s*)?noon\z/)
    return "00:00" if text.match?(/\A(12(:00)?\s*)?midnight\z/)

    match = text.match(/\A(\d{1,2})(?:[:.]?(\d{2}))?\s*(?:([ap])(?:\.?\s*m)?\.?)?\z/)
    return nil unless match

    hour = match[1].to_i
    minute = match[2].to_i
    meridian = match[3]
    return nil if minute > 59

    if meridian
      return nil unless (1..12).cover?(hour)
      hour = 0 if hour == 12
      hour += 12 if meridian == "p"
    else
      return nil if hour > 23
      hour += 12 if (1..LAST_ASSUMED_PM_HOUR).cover?(hour) && !match[1].start_with?("0")
    end

    format("%02d:%02d", hour, minute)
  end

  # True for input that is evidently meant to be a time of day, as opposed to
  # free text.
  def self.time_like?(value)
    value.to_s.strip.match?(TIME_LIKE)
  end

  # Friendly display form: "13:00" -> "1:00 PM".  Free text is returned
  # unchanged.
  def self.display(value)
    canonical = parse(value)
    return value.to_s unless canonical

    hour, minute = canonical.split(":").map(&:to_i)
    meridian = hour < 12 ? "AM" : "PM"
    hour12 = hour % 12
    hour12 = 12 if hour12 == 0
    format("%d:%02d %s", hour12, minute, meridian)
  end

  private

  def start_time_recognized
    return if time.blank? || StartTime.parse(time) == time || !StartTime.time_like?(time)
    errors.add(:time, "\"#{time}\" isn't a time we recognize. Try something like 8:30 am or 1 pm")
  end
end
