namespace :job_matching do
  desc "Match open job postings to resumes and email the results. USER_EMAIL=one user instead of those with auto-analysis, SINCE=YYYY-MM-DD instead of a week ago"
  task run: :environment do
    since = ENV["SINCE"].presence&.then { |date| Date.iso8601(date) }
    results = JobMatching::Run.new(user_email: ENV["USER_EMAIL"].presence, since: since).call

    results.each { |result| puts result.to_json }
    undelivered = MatchResultsMailer.deliver_matches(results)

    failures = results.select(&:failed?)
    abort "Matching failed for #{failures.size} of #{results.size} users" if failures.any?
    abort "Emailing failed for #{undelivered.size} users" if undelivered.any?
  end
end
