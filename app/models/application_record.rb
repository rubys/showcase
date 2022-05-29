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
      record.errors.add attribute, (options[:message] || "is not an day/time") unless
        Chronic.parse(value.sub(/(^|[a-z]+ )?\d+-\d+/) {|str| str.sub(/-.*/, '')})
    end
  end
end
