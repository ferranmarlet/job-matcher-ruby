require "test_helper"

class McpTest < ActionDispatch::IntegrationTest
  include CognitoTokens
  include ActionMailer::TestHelper

  setup do
    host! "localhost"
    JobMatcherMcp.token_verifier = cognito_verifier
  end

  teardown do
    JobMatcherMcp.token_verifier = nil
  end

  test "requires a Cognito access token" do
    post_mcp("tools/list", token: nil)

    assert_response :unauthorized
  end

  test "refuses users outside the admin group" do
    post_mcp("tools/list", token: cognito_access_token("cognito:groups": [ "users" ]))

    assert_response :forbidden
  end

  test "lists the tools" do
    post_mcp("tools/list")

    assert_response :success
    assert_equal %w[match_jobs refine_matches], response.parsed_body.dig("result", "tools").map { |tool| tool["name"] }.sort
  end

  test "matches jobs for a user" do
    stub_aws_matching([ { "job_posting_id" => job_posting(:recent_open).id, "score" => 88, "reasons" => "Ruby", "gaps" => "None" } ])

    post_mcp("tools/call", params: { name: "match_jobs", arguments: { user_email: "alice@example.com" } })

    assert_response :success
    result = JSON.parse(response.parsed_body.dig("result", "content", 0, "text"))
    assert_equal "alice@example.com", result.sole["user_email"]
    assert_equal [ 88 ], result.sole["matches"].map { |match| match["score"] }
  end

  test "emails the matches only when asked" do
    stub_aws_matching([ { "job_posting_id" => job_posting(:recent_open).id, "score" => 88, "reasons" => "Ruby", "gaps" => "None" } ])

    assert_no_emails { post_mcp("tools/call", params: { name: "match_jobs", arguments: { user_email: "alice@example.com" } }) }
    assert_emails(1) do
      post_mcp("tools/call", params: { name: "match_jobs", arguments: { user_email: "alice@example.com", send_email: true } })
    end
  end

  test "reports an invalid date as a tool error" do
    post_mcp("tools/call", params: { name: "match_jobs", arguments: { since: "last week" } })

    assert response.parsed_body.dig("result", "isError")
    assert_equal "since must be a date formatted as YYYY-MM-DD", response.parsed_body.dig("result", "content", 0, "text")
  end

  test "treats an empty email as an unknown user, not as everyone" do
    post_mcp("tools/call", params: { name: "match_jobs", arguments: { user_email: "" } })

    assert response.parsed_body.dig("result", "isError")
  end

  test "reports an unknown user as a tool error" do
    post_mcp("tools/call", params: { name: "match_jobs", arguments: { user_email: "nobody@example.com" } })

    assert_response :success
    assert response.parsed_body.dig("result", "isError")
    assert_equal "No user has the email nobody@example.com", response.parsed_body.dig("result", "content", 0, "text")
  end

  test "refines a user's matches" do
    stub_aws_matching([ { "job_posting_id" => job_posting(:old_open).id, "score" => 75, "reasons" => "Java", "gaps" => "None" } ])

    post_mcp("tools/call", params: {
      name: "refine_matches",
      arguments: {
        user_email: "alice@example.com",
        previous_matches: [ { job_posting_id: job_posting(:old_open).id, score: 60 } ],
        feedback: "I prefer Java"
      }
    })

    assert_response :success
    result = JSON.parse(response.parsed_body.dig("result", "content", 0, "text"))
    assert_equal [ job_posting(:old_open).id ], result["matches"].map { |match| match["job_posting_id"] }
  end

  private

  def post_mcp(method, params: {}, token: cognito_access_token)
    headers = { "Accept" => "application/json, text/event-stream", "MCP-Protocol-Version" => "2025-06-18" }
    headers["Authorization"] = "Bearer #{token}" if token
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
      headers: headers.merge("Content-Type" => "application/json")
  end
end
