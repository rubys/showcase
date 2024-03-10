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
end
