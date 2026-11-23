class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.env.production? ? ENV.fetch("SES_SENDER_EMAIL") : ENV.fetch("SES_SENDER_EMAIL", "job-matcher@example.com") }
  layout "mailer"
end
