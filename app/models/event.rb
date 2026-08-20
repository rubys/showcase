require 'ostruct'

class Event < ApplicationRecord
  include BlobUploadable

  validate :valid_date?
  has_one_attached :counter_art, dependent: false
  validate :correct_document_mime_type

  belongs_to :solo_level, class_name: 'Level', optional: true

  after_save :upload_blobs, if: -> { counter_art.attached? && counter_art.blob.created_at > 1.minute.ago }
  after_save :ensure_nobody_exists, if: -> { saved_change_to_partnerless_entries? && partnerless_entries? }

  @@current = nil
  def self.current
    @@current ||= Event.sole
  end

  def self.current=(event)
    @@current = event
  end

  def self.list
    showcases = ShowcasesLoader.load

    results = []

    showcases.sort.each do |year, list|
      list.each do |token, info|
        if info[:events]
          info[:events].each do |subtoken, subinfo|
            results << OpenStruct.new(
              studio: token,
              owner:  info[:name],
              region: info[:region],
              name:   info[:name] + ' - ' + subinfo[:name] ,
              label:  "#{year}-#{token}-#{subtoken}",
              scope:  "#{year}/#{token}/#{subtoken}",
              logo:   info[:logo],
            )
          end
        else
          results << OpenStruct.new(
            studio: token,
            owner:  info[:name],
            region: info[:region],
            name:   info[:name],
            label:  "#{year}-#{token}",
            scope:  "#{year}/#{token}",
            logo:   info[:logo],
          )
        end
      end
    end

    return results
  end

  def self.parse_date(date, options={})
    return unless date

    if date =~ /^\d+-\d+-\d+$/
      date = date.gsub('-', '/')
    elsif date =~ /^(\d+-\d+-\d+) - (\d+-\d+-\d+)$/
      return parse_date($1, options) || parse_date($2, options)
    elsif date !~ /^\d+\//
      date = date.sub(/((^|[a-z]+\s+)\d+)(-|\sand\s|\/|\s*&\s*)\d+/, '\1')
    end

    Chronic.parse(date, options)
  end

  def valid_date?
    unless date.blank? || Event.parse_date(date)
      errors.add(:date, "is missing or invalid")
    end
  end

  def correct_document_mime_type
    acceptable_types = %w(image/apng image/avif image/gif image/jpeg image/png
      image/svg+xml image/webp video/webm video/mp4)
    if counter_art.attached? && !counter_art.content_type.in?(acceptable_types)
      errors.add(:counter_art, 'Must be an image or video')
    end
  end

  def download_counter_art
    download_blob(counter_art.blob)
  end

  # Scoring styles that collect Good / Needs Work feedback buttons.
  FEEDBACK_STYLES = %w(+ & @).freeze

  # Scoring style in effect for heats in the given category.
  #
  # Closed heats follow the open style when closed_scoring is '=' or when open
  # and closed heats are combined into a single agenda category
  # (heat_range_cat > 0).  Anything that is not a recognized heat category
  # scores like an open heat.
  def scoring_for(category)
    case category
    when 'Solo' then solo_scoring
    when 'Multi' then multi_scoring
    when 'Closed'
      closed_follows_open? ? open_scoring : closed_scoring
    else open_scoring
    end
  end

  # Do heats in the given category collect Good / Needs Work feedback?
  def feedback_scoring?(category)
    FEEDBACK_STYLES.include? scoring_for(category)
  end

  # The feedback style in use, or nil when no category collects feedback.  An
  # event can mix styles -- placements for open heats, 1-5 plus feedback for
  # closed ones -- and this is the one that names the feedback buttons.
  def feedback_style
    %w(Open Closed).map { |category| scoring_for(category) }.
      find { |style| FEEDBACK_STYLES.include? style }
  end

  # Does any category of heat collect feedback?  Used to decide whether to
  # offer the feedback-capable scoring interface and print feedback grids.
  def any_feedback_scoring?
    feedback_style.present?
  end

  # Closed heats are scored the same way as open heats, either because the
  # closed style is literally "same as open" or because the two are scheduled
  # into a single agenda category.
  def closed_follows_open?
    closed_scoring == '=' || heat_range_cat.to_i > 0
  end

private

  def ensure_nobody_exists
    return if Person.exists?(0)

    # Find or create Event Staff studio
    event_staff = Studio.find_or_create_by(name: 'Event Staff') do |s|
      s.tables = 0
    end

    # Get first level for Nobody
    first_level = Level.order(:id).first

    # Create Nobody person
    Person.create!(
      id: 0,
      name: 'Nobody',
      type: 'Student',
      studio: event_staff,
      level: first_level,
      back: 0
    )
  end
end
