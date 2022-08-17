class Score < ApplicationRecord
  belongs_to :judge, nil, class_name: 'Person'
  belongs_to :heat
  # validates_associated :heat # Too dangerous to validate during scoring

  after_save do |score|
    STDERR.puts 'touched'
    score.broadcast_replace_later_to "live-scores-#{ENV['RAILS_APP_DB']}",
      partial: 'scores/last_update', target: 'last-score-update',
      locals: {timestamp: score.updated_at}
  end
end
