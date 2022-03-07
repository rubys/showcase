class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  @@readonly_showcase = Rails.application.config.database_configuration[Rails.env]['readonly']

  def readonly?
    @@readonly_showcase || super
  end

  def self.readonly?
    !!@@readonly_showcase
  end
end
