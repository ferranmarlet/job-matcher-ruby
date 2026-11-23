class MatchJobsTool < ApplicationTool
  tool_name "match_jobs"
  description <<~DESCRIPTION
    Matches open job postings to users' resumes with AI and returns the matching postings with a score, why they fit and what the candidate lacks.
    Without user_email, it matches every user with auto-analysis enabled. Results are not stored.
  DESCRIPTION
  input_schema(
    properties: {
      user_email: { type: "string", description: "Match only this user, whether or not auto-analysis is enabled." },
      since: SINCE_PROPERTY,
      send_email: { type: "boolean", description: "Also email each user their matches. Defaults to false." }
    }
  )

  class << self
    def call(server_context:, user_email: nil, since: nil, send_email: false)
      reporting_input_errors(user_email) do
        results = JobMatching::Run.new(user_email: user_email, since: parse_date(since)).call
        undelivered = send_email ? MatchResultsMailer.deliver_matches(results) : []
        json_response(results.as_json, note: undelivered_note(undelivered))
      end
    end

    private

    def undelivered_note(undelivered)
      "Could not email: #{undelivered.map { |result| result.user.email }.join(', ')}" if undelivered.any?
    end
  end
end
