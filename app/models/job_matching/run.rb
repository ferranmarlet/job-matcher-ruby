module JobMatching
  class Run
    DEFAULT_LOOKBACK = 1.week

    def initialize(user_email: nil, since: nil, matcher: nil, resume_storage: nil)
      @user_email = user_email
      @since = since&.beginning_of_day || DEFAULT_LOOKBACK.ago
      @matcher = matcher
      @resume_storage = resume_storage
    end

    def call
      postings = job_postings.to_a
      users.map { |user| match_user(user, postings) }
    end

    def refine(previous_matches:, feedback:)
      raise ArgumentError, "Refining matches needs a user email" if @user_email.nil?

      user = users.first
      postings = job_postings(including_ids: previous_matches.map { |match| match["job_posting_id"] }).to_a

      with_failures_reported(user) do
        matcher.refine(
          resume_pdf: resume_storage.download(user.resume),
          job_postings: postings,
          previous_matches: previous_matches,
          feedback: feedback
        )
      end
    end

    private

    def matcher
      @matcher ||= Matcher.new
    end

    def resume_storage
      @resume_storage ||= ResumeStorage.new
    end

    def users
      scope = User.includes(:resume)
      @user_email ? [ scope.find_by!(email: @user_email) ] : scope.with_auto_analysis.to_a
    end

    def job_postings(including_ids: [])
      recent = JobPosting.currently_open.discovered_since(@since)
      recent.or(JobPosting.where(id: including_ids)).includes(:skills)
    end

    def match_user(user, postings)
      with_failures_reported(user) do
        next [] if postings.empty?

        matcher.match(resume_pdf: resume_storage.download(user.resume), job_postings: postings)
      end
    end

    def with_failures_reported(user)
      return UserMatches.skipped(user, "User has no resume") if user.resume.nil?

      UserMatches.matched(user, yield)
    rescue ResumeStorage::UnusableResumeError, Aws::Errors::ServiceError, Seahorse::Client::NetworkingError,
           Matcher::InvalidResponseError => error
      Rails.logger.error("Matching failed for user #{user.id}: #{error.class}: #{error.message}")
      UserMatches.failed(user, error.message)
    end
  end
end
