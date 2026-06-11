class Feedback < ApplicationRecord
  # Rails 8.0 compatible ordering scope
  scope :ordered, -> { order(arel_table[:order]) }

  # Feedback items as [abbr, value] pairs. When no records are configured,
  # fall back to the same defaults the judge scoring interface displays
  # (which vary by open scoring style).
  def self.items(open_scoring = nil)
    if any?
      ordered.map { |f| [f.abbr, f.value] }
    elsif open_scoring == '+'
      [
        ['DF', 'Dance Frame'], ['T', 'Timing'], ['LF', 'Lead/Follow'],
        ['CM', 'Cuban Motion'], ['RF', 'Rise & Fall'], ['FW', 'Footwork'],
        ['B', 'Balance'], ['AS', 'Arm Styling'], ['CB', 'Contra-Body'], ['FC', 'Floor Craft']
      ]
    else
      [
        ['F', 'Frame'], ['P', 'Posture'], ['FW', 'Footwork'],
        ['LF', 'Lead/Follow'], ['T', 'Timing'], ['S', 'Styling']
      ]
    end
  end
end
