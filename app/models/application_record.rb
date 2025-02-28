class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  @@readonly_showcase = Rails.application.config.database_configuration[Rails.env]['readonly']

  def readonly?
    @@readonly_showcase || super
  end

  def self.readonly?
    !!@@readonly_showcase
  end

  class ChronicValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      record.errors.add attribute, (options[:message] || "is not an day/time") unless Event.parse_date(value)
    end
  end

  # stub normalizes until 7.1 upgrade
  unless respond_to? :normalizes
    def self.normalizes *args
    end
  end

  RAILS_STORAGE = Pathname.new(ENV.fetch("RAILS_STORAGE", Rails.root.join("storage")))

  def download_blob(blob)
    return # unless ENV['FLY_REGION']

    Thread.new do
      sleep 5
      dest = RAILS_STORAGE.join(blob.key.sub(/(..)(..)/, '\1/\2/\1\2'))
      FileUtils.mkdir_p File.dirname(dest)
      File.open(dest, 'wb') do |file|
        file.binmode
        counter_art.blob.download { |chunk| file.write(chunk) }
        file.flush
      end
    end
  end
end
