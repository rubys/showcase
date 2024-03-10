class Event < ApplicationRecord
  validate :valid_date?
  has_one_attached :counter_art
  validate :correct_document_mime_type

  belongs_to :solo_level, class_name: 'Level', optional: true

  def self.list
    showcases = YAML.load_file("#{__dir__}/../../config/tenant/showcases.yml")

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

    if date =~ /^\d+-\d+-\d+/
      date = date.gsub('-', '/')
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
    acceptable_types = "image/apng,image/avif,image/gif,image/jpeg,image/png,image/svg+xml,image/webp".split(',')
    if counter_art.attached? && !counter_art.content_type.in?(acceptable_types)
      errors.add(:counter_art, 'Must be an image')
    end
  end
end
