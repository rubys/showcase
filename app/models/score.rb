class Score < ApplicationRecord
  belongs_to :judge, nil, class_name: 'Person'
  belongs_to :heat
  # validates_associated :heat # Too dangerous to validate during scoring

  after_save do |score|
    broadcast_replace_later_to "live-scores-#{ENV['RAILS_APP_DB']}",
      partial: 'scores/last_update', target: 'last-score-update',
      locals: {action: nil, timestamp: score.updated_at}
  end

  before_destroy do
    broadcast_replace_to "live-scores-#{ENV['RAILS_APP_DB']}",
      partial: 'scores/last_update', target: 'last-score-update',
      locals: {action: nil, timestamp: Time.zone.now}
  end
end
