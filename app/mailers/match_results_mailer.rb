class MatchResultsMailer < ApplicationMailer
  def self.deliver_matches(results)
    results.select { |result| result.matches.any? }.reject do |result|
      with(user_matches: result).results.deliver_now
    rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => error
      Rails.logger.error("Emailing matches to user #{result.user.id} failed: #{error.class}: #{error.message}")
      false
    end
  end

  def results
    @matches = params[:user_matches].matches
    mail to: params[:user_matches].user.email, subject: subject_for(@matches.size)
  end

  private

  def subject_for(count)
    count == 1 ? "1 job posting matches your resume" : "#{count} job postings match your resume"
  end
end
