require "test_helper"

class JobMatching::UserMatchesTest < ActiveSupport::TestCase
  test "describes the matched postings" do
    match = JobMatching::Match.new(job_posting: job_posting(:recent_open), score: 90, reasons: "Ruby", gaps: "Kafka")

    json = JobMatching::UserMatches.matched(users(:alice), [ match ]).as_json

    assert_equal "alice@example.com", json["user_email"]
    assert_equal(
      { "job_posting_id" => job_posting(:recent_open).id, "title" => "Ruby developer", "company" => "Acme",
        "source_url" => "https://jobs.example.com/1", "score" => 90, "reasons" => "Ruby", "gaps" => "Kafka" },
      json["matches"].sole
    )
    assert_not json.key?("error")
    assert_not json.key?("skipped")
  end

  test "reports why a user was skipped or failed" do
    assert_equal "User has no resume", JobMatching::UserMatches.skipped(users(:carol), "User has no resume").as_json["skipped"]
    assert_equal "Throttled", JobMatching::UserMatches.failed(users(:alice), "Throttled").as_json["error"]
  end
end
