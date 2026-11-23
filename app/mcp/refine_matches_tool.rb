class RefineMatchesTool < ApplicationTool
  tool_name "refine_matches"
  description <<~DESCRIPTION
    Revises a user's matches, as returned by match_jobs, following feedback such as "only remote jobs" or "I don't want to work with PHP".
    Returns the complete revised list. Results are not stored.
  DESCRIPTION
  input_schema(
    properties: {
      user_email: { type: "string", description: "The user whose matches are refined." },
      previous_matches: {
        type: "array",
        description: "The user's matches as returned by match_jobs.",
        items: {
          type: "object",
          properties: {
            job_posting_id: { type: "string" },
            score: { type: "integer" },
            reasons: { type: "string" },
            gaps: { type: "string" }
          },
          required: %w[job_posting_id]
        }
      },
      feedback: { type: "string", description: "How the matches should change." },
      since: SINCE_PROPERTY
    },
    required: %w[user_email previous_matches feedback]
  )

  class << self
    def call(server_context:, user_email:, previous_matches:, feedback:, since: nil)
      reporting_input_errors(user_email) do
        result = JobMatching::Run.new(user_email: user_email, since: parse_date(since))
          .refine(previous_matches: previous_matches.map(&:deep_stringify_keys), feedback: feedback)
        json_response(result.as_json)
      end
    end
  end
end
