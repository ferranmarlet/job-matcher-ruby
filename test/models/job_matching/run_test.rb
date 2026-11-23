require "test_helper"

class JobMatching::RunTest < ActiveSupport::TestCase
  class FakeMatcher
    attr_reader :calls

    def initialize
      @calls = []
    end

    def match(resume_pdf:, job_postings:)
      @calls << { resume_pdf: resume_pdf, job_postings: job_postings }
      job_postings.map { |posting| JobMatching::Match.new(job_posting: posting, score: 90, reasons: "Fits", gaps: "None") }
    end

    def refine(resume_pdf:, job_postings:, previous_matches:, feedback:)
      @calls << { resume_pdf: resume_pdf, job_postings: job_postings, previous_matches: previous_matches, feedback: feedback }
      []
    end
  end

  class FakeResumeStorage
    def download(resume)
      "%PDF-#{resume.file_link}"
    end
  end

  class NonPdfResumeStorage
    def download(resume)
      raise JobMatching::ResumeStorage::UnusableResumeError, "Resume #{resume.id} is not a PDF"
    end
  end

  class FailingResumeStorage
    def initialize(error)
      @error = error
    end

    def download(_resume)
      raise @error
    end
  end

  setup do
    @matcher = FakeMatcher.new
  end

  test "matches the users with auto-analysis to the open postings of the last week" do
    results = matching_run.call

    assert_equal [ users(:alice), users(:carol) ].sort_by(&:id), results.map(&:user).sort_by(&:id)
    alice = results.find { |result| result.user == users(:alice) }
    assert_equal [ job_posting(:recent_open) ], alice.matches.map(&:job_posting)
    assert_equal "%PDF-resumes/alice.pdf", @matcher.calls.sole[:resume_pdf]
  end

  test "reports users without a resume" do
    carol = matching_run.call.find { |result| result.user == users(:carol) }

    assert_equal "User has no resume", carol.skipped_reason
    assert_not carol.failed?
  end

  test "matches a single user, even without auto-analysis" do
    results = matching_run(user_email: "bob@example.com").call

    assert_equal [ users(:bob) ], results.map(&:user)
  end

  test "matches postings discovered since a given date" do
    matching_run(user_email: "alice@example.com", since: 15.days.ago.to_date).call

    assert_equal [ job_posting(:old_open), job_posting(:recent_open) ].sort_by(&:id),
      @matcher.calls.sole[:job_postings].sort_by(&:id)
  end

  test "fails for an unknown user" do
    assert_raises(ActiveRecord::RecordNotFound) { matching_run(user_email: "nobody@example.com").call }
  end

  test "reports a resume that cannot be matched without stopping the run" do
    results = matching_run(resume_storage: NonPdfResumeStorage.new).call

    alice = results.find { |result| result.user == users(:alice) }
    assert_match "is not a PDF", alice.error
  end

  test "refines a user's matches, including previously matched postings that are no longer recent" do
    previous = [ { "job_posting_id" => job_posting(:old_open).id, "score" => 80 } ]

    result = matching_run(user_email: "alice@example.com").refine(previous_matches: previous, feedback: "Only Java")

    assert_nil result.error
    call = @matcher.calls.sole
    assert_includes call[:job_postings], job_posting(:old_open)
    assert_includes call[:job_postings], job_posting(:recent_open)
    assert_equal "Only Java", call[:feedback]
  end

  test "reports AWS and network failures without stopping the run" do
    [
      Aws::S3::Errors::NoSuchKey.new(nil, "The specified key does not exist."),
      Seahorse::Client::NetworkingError.new(Net::ReadTimeout.new, "Net::ReadTimeout")
    ].each do |error|
      alice = matching_run(resume_storage: FailingResumeStorage.new(error)).call.find { |result| result.user == users(:alice) }

      assert alice.failed?, "did not report #{error.class}"
    end
  end

  test "does not call the matcher when there are no recent postings" do
    results = matching_run(user_email: "alice@example.com", since: 1.day.from_now.to_date).call

    assert_empty results.sole.matches
    assert_empty @matcher.calls
  end

  test "skips refining for a user without a resume" do
    result = matching_run(user_email: "carol@example.com").refine(previous_matches: [], feedback: "Anything")

    assert_equal "User has no resume", result.skipped_reason
    assert_empty @matcher.calls
  end

  test "refining needs a user" do
    assert_raises(ArgumentError) { matching_run.refine(previous_matches: [], feedback: "Anything") }
  end

  private

  def matching_run(resume_storage: FakeResumeStorage.new, **options)
    JobMatching::Run.new(matcher: @matcher, resume_storage: resume_storage, **options)
  end
end
