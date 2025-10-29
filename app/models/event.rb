require 'ostruct'

class Event < ApplicationRecord
  validate :valid_date? unless Rails.env.test?
  has_one_attached :counter_art, dependent: false
  validate :correct_document_mime_type

  belongs_to :solo_level, class_name: 'Level', optional: true

  after_save :upload_blobs, if: -> { counter_art.attached? && counter_art.blob.created_at > 1.minute.ago }

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
end
