require 'chronic'

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
      # In test environment, Event.parse_date might not be loaded yet
      if defined?(Event) && Event.respond_to?(:parse_date)
        record.errors.add attribute, (options[:message] || "is not an day/time") unless Event.parse_date(value)
      else
        # Fallback for when Event isn't loaded - just check if value is present
        record.errors.add attribute, (options[:message] || "is not an day/time") if value.present? && !Chronic.parse(value)
      end
    end
  end


  RAILS_STORAGE = Pathname.new(ENV.fetch("RAILS_STORAGE", Rails.root.join("storage")))

  def upload_blobs
    return unless ENV['FLY_REGION']

    local_attachments = ActiveStorage::Attachment.joins(:blob).where(blob: {service_name: 'local'})

    return unless local_attachments.any?

    Thread.new do
      sleep 1

      s3 = Aws::S3::Client.new(
        region: "auto",
        endpoint: "https://fly.storage.tigris.dev",
        force_path_style: false,
      )

      local_attachments = ActiveStorage::Attachment.joins(:blob).where(blob: {service_name: 'local'})
      local_attachments.each do |attachment|
        next unless attachment.blob.service_name == 'local'
        blob = RAILS_STORAGE.join(attachment.blob.key.sub(/(..)(..)/, '\1/\2/\1\2'))

        logger.info "Uploading #{blob} to tigris"

        File.open(blob, 'rb') do |file|
          s3.put_object(
            bucket: ENV['BUCKET_NAME'],
            key: attachment.blob.key,
            body: file,
            content_type: attachment.blob.content_type,
          )
        end

        attachment.blob.update!(service_name: 'tigris')
      end

    end
  end

  def download_blob(blob)
    return # unless ENV['FLY_REGION']
    return unless blob.service_name == 'tigris'

    dest = RAILS_STORAGE.join(blob.key.sub(/(..)(..)/, '\1/\2/\1\2'))
    return if File.exist?(dest)

    Thread.new do
      sleep 5

      FileUtils.mkdir_p File.dirname(dest)
      File.open(dest, 'wb') do |file|
        file.binmode
        blob.download { |chunk| file.write(chunk) }
        file.flush
      end
    end
  end
end
