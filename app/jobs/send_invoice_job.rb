class SendInvoiceJob < ApplicationJob
  queue_as :default

  def perform(invoice_url, params)
    file = Tempfile.new('invoice.pdf')

    if RUBY_PLATFORM =~ /darwin/
      chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    else
      chrome="google-chrome"
    end

    `#{chrome.inspect} --headless --disable-gpu --print-to-pdf=#{file.path} --print-to-pdf-no-header #{invoice_url}`

    filename = ENV.fetch("RAILS_APP_DB") { 'showcase' } + '-invoice.pdf'

    mail = Mail.new do
      from params['from']
      to params['to']
      subject params['subject']

      html_part do
        content_type 'text/html; charset=UTF-8'
        body params['body']
      end

      add_file filename: filename, content: File.read(file.path)
    end

    mail.delivery_method :smtp,
      Rails.application.credentials.smtp || { address: 'mail.twc.com' }

    mail.deliver!
  ensure 
    file.delete
  end
end
