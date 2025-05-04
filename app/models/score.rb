class Score < ApplicationRecord
  belongs_to :judge, nil, class_name: 'Person'
  belongs_to :heat
  # validates_associated :heat # Too dangerous to validate during scoring

  after_save do |score|
    next unless score.value || score.comments || score.good || score.bad
    broadcast_replace_later_to "live-scores-#{ENV['RAILS_APP_DB']}",
      partial: 'scores/last_update', target: 'last-score-update',
      locals: {action: false, timestamp: score.updated_at}
  end

  before_destroy do |score|
    next unless score.value || score.comments || score.good || score.bad
    broadcast_replace_to "live-scores-#{ENV['RAILS_APP_DB']}",
      partial: 'scores/last_update', target: 'last-score-update',
      locals: {action: false, timestamp: Time.zone.now}
  end

  def display_value
    if value.start_with?('{')
      # This is a JSON object, so we need to parse it
      JSON.parse(value).map {|k, v| "#{k}: #{v}" }.join(', ')
    else
      value
    end
  end
end
