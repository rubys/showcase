# Start times for agenda items (categories and category extensions).
#
# Times are entered in a plain text field so they work the same in every
# browser (Safari-based browsers such as DuckDuckGo render <input type="time">
# as a segmented control that silently rejects typed text like "8:30 am").
#
# Whatever the user types is normalized to 24-hour "HH:MM", which is the form
# the scheduler (Printable#generate_agenda) handles most directly.  Values that
# can't be understood are rejected with a helpful message rather than being
# saved and then ignored when start times are computed.
module StartTime
  extend ActiveSupport::Concern

  CANONICAL = /\A\d{2}:\d{2}\z/

  included do
    normalizes :time, with: ->(value) { StartTime.parse(value) || value.strip }
    validate :start_time_recognized, if: :time_changed?
  end

  # Returns "HH:MM" (24-hour) for recognizable input, nil otherwise.
  #
  # Accepts: "8:30 am", "8:30am", "8:30 a.m.", "8 pm", "8p", "830 pm",
  # "13:00", "1300", "8.30", "noon", "12 noon", "midnight".
  # Without am/pm the hour is read as 24-hour time ("1:00" is 1:00 AM).
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
    end

    format("%02d:%02d", hour, minute)
  end

  # Friendly display form: "13:00" -> "1:00 PM".  Unrecognized values are
  # returned unchanged so the user can see (and fix) what they typed.
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
    return if time.blank? || time.match?(CANONICAL)
    errors.add(:time, "\"#{time}\" isn't a time we recognize. Try something like 8:30 am or 1 pm")
  end
end
