class Event < ApplicationRecord
  validate :valid_date?
  has_one_attached :counter_art

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

  def valid_date?
    unless date.blank? || Chronic.parse(date)
      errors.add(:date, "is missing or invalid")
    end
  end
end
