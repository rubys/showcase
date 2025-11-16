class Score < ApplicationRecord
  belongs_to :judge, nil, class_name: 'Person'
  belongs_to :heat, optional: true  # Optional because category scores don't reference a heat
  belongs_to :person, optional: true  # Student receiving this score (for category scores)
  # validates_associated :heat # Too dangerous to validate during scoring

  # Scopes for different score types
  scope :category_scores, -> { where('heat_id < 0') }
  scope :heat_scores, -> { where('heat_id > 0') }

  # Validation: person_id required for category scores
  validates :person_id, presence: true, if: :category_score?

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
    return unless value
    if value.start_with?('{')
      # This is a JSON object, so we need to parse it
      JSON.parse(value).map {|k, v| "#{k}: #{v}" }.join(', ')
    else
      value
    end
  end

  # Category scoring helpers
  def category_score?
    heat_id&.negative?
  end

  def per_heat_score?
    heat_id&.positive?
  end

  def actual_category_id
    -heat_id if category_score?
  end

  def actual_category
    Category.find(actual_category_id) if category_score?
  end

  def actual_heat
    Heat.find(heat_id) if per_heat_score?
  end
end
