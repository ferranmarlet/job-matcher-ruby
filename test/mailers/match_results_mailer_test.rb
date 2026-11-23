require "test_helper"

class MatchResultsMailerTest < ActionMailer::TestCase
  class FailingDelivery
    def initialize(_settings); end

    def deliver!(_mail)
      raise Aws::SESV2::Errors::MessageRejected.new(nil, "Email address is not verified.")
    end
  end

  ActionMailer::Base.add_delivery_method :failing, FailingDelivery

  setup do
    @match = JobMatching::Match.new(job_posting: job_posting(:recent_open), score: 92, reasons: "Knows Ruby", gaps: "No Kafka")
  end

  test "emails each user who has matches" do
    results = [
      JobMatching::UserMatches.matched(users(:alice), [ @match ]),
      JobMatching::UserMatches.matched(users(:bob), []),
      JobMatching::UserMatches.skipped(users(:carol), "User has no resume")
    ]

    undelivered = nil
    assert_emails(1) { undelivered = MatchResultsMailer.deliver_matches(results) }

    assert_empty undelivered
    email = ActionMailer::Base.deliveries.last
    assert_equal [ "alice@example.com" ], email.to
    assert_equal "1 job posting matches your resume", email.subject
    assert_includes email.text_part.body.to_s, "Ruby developer at Acme (score 92/100)"
    assert_includes email.text_part.body.to_s, "https://jobs.example.com/1"
    assert_includes email.html_part.body.to_s, "No Kafka"
  end

  test "counts the matches in the subject" do
    result = JobMatching::UserMatches.matched(users(:alice), [ @match, @match.with(job_posting: job_posting(:old_open)) ])

    assert_equal "2 job postings match your resume", MatchResultsMailer.with(user_matches: result).results.subject
  end

  test "keeps emailing the other users when one email fails" do
    results = [ JobMatching::UserMatches.matched(users(:alice), [ @match ]), JobMatching::UserMatches.matched(users(:bob), [ @match ]) ]

    undelivered = with_delivery_method(:failing) { MatchResultsMailer.deliver_matches(results) }

    assert_equal [ users(:alice), users(:bob) ], undelivered.map(&:user)
  end

  test "does not link job posting URLs that are not web pages" do
    posting = JobPosting.new(id: "1", title: "Ruby developer", source_url: "javascript:alert(1)")
    result = JobMatching::UserMatches.matched(users(:alice), [ @match.with(job_posting: posting) ])

    html = MatchResultsMailer.with(user_matches: result).results.html_part.body.to_s

    assert_includes html, "Ruby developer"
    assert_not_includes html, "javascript:"
  end

  private

  def with_delivery_method(method)
    previous = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = method
    yield
  ensure
    ActionMailer::Base.delivery_method = previous
  end
end
