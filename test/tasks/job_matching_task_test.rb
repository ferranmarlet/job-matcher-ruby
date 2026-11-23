require "test_helper"
require "rake"

class JobMatchingTaskTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "job_matching:run" }
    Rake::Task["job_matching:run"].reenable
  end

  teardown do
    ENV.delete("USER_EMAIL")
    ENV.delete("SINCE")
  end

  test "emails the matches and prints every result" do
    stub_aws_matching([ { "job_posting_id" => job_posting(:recent_open).id, "score" => 90, "reasons" => "Ruby", "gaps" => "None" } ])

    output = nil
    assert_emails(1) { output, = capture_io { Rake::Task["job_matching:run"].invoke } }

    lines = output.lines.map { |line| JSON.parse(line) }
    assert_equal %w[alice@example.com carol@example.com], lines.map { |line| line["user_email"] }.sort
  end

  test "matches the given user since the given date" do
    stub_aws_matching([ { "job_posting_id" => job_posting(:old_open).id, "score" => 70, "reasons" => "Java", "gaps" => "None" } ])
    ENV["USER_EMAIL"] = "bob@example.com"
    ENV["SINCE"] = 15.days.ago.to_date.iso8601

    output, = capture_io { Rake::Task["job_matching:run"].invoke }

    assert_equal [ job_posting(:old_open).id ], JSON.parse(output).fetch("matches").map { |match| match["job_posting_id"] }
  end

  test "fails when a user's matching fails" do
    Aws.config[:s3] = { stub_responses: { get_object: { body: "not a pdf" } } }

    assert_raises(SystemExit) { capture_io { Rake::Task["job_matching:run"].invoke } }
  end
end
