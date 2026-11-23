require "test_helper"

class JobMatching::MatcherTest < ActiveSupport::TestCase
  setup do
    @postings = [ job_posting(:recent_open), job_posting(:old_open) ]
  end

  test "sends the resume as a PDF document and forces the matches tool" do
    client = bedrock_client(bedrock_response([]))

    JobMatching::Matcher.new(client: client, model_id: "test-model").match(resume_pdf: RESUME_PDF, job_postings: @postings)

    params = client.api_requests.first[:params]
    content = params[:messages].first[:content]
    assert_equal "test-model", params[:model_id]
    assert_equal({ format: "pdf", name: "resume", source: { bytes: RESUME_PDF } }, content.first[:document])
    assert_includes content.last[:text], job_posting(:recent_open).id
    assert_equal({ tool: { name: "record_matches" } }, params[:tool_config][:tool_choice])
    assert_equal JobMatching::Matcher::MAX_TOKENS, params[:inference_config][:max_tokens]
  end

  test "returns the reported matches, best first" do
    client = bedrock_client(bedrock_response([
      { "job_posting_id" => job_posting(:old_open).id, "score" => 70, "reasons" => "Java", "gaps" => "Spring" },
      { "job_posting_id" => job_posting(:recent_open).id, "score" => 95, "reasons" => "Ruby", "gaps" => "None" }
    ]))

    matches = JobMatching::Matcher.new(client: client).match(resume_pdf: RESUME_PDF, job_postings: @postings)

    assert_equal [ job_posting(:recent_open), job_posting(:old_open) ], matches.map(&:job_posting)
    assert_equal [ 95, 70 ], matches.map(&:score)
    assert_equal "Ruby", matches.first.reasons
  end

  test "drops low scores and postings it was not given" do
    client = bedrock_client(bedrock_response([
      { "job_posting_id" => job_posting(:recent_open).id, "score" => 40, "reasons" => "", "gaps" => "" },
      { "job_posting_id" => "made-up-id", "score" => 99, "reasons" => "", "gaps" => "" }
    ]))

    assert_empty JobMatching::Matcher.new(client: client).match(resume_pdf: RESUME_PDF, job_postings: @postings)
  end

  test "fails when the model stops before reporting the matches" do
    client = bedrock_client(bedrock_response([], stop_reason: "max_tokens"))

    assert_raises(JobMatching::Matcher::InvalidResponseError) do
      JobMatching::Matcher.new(client: client).match(resume_pdf: RESUME_PDF, job_postings: @postings)
    end
  end

  test "fails when the matches come back in an unexpected format" do
    [ "[{\"job_posting_id\": \"1\"}]", [ "not an object" ], nil ].each do |reported|
      client = bedrock_client(bedrock_response(reported))

      assert_raises(JobMatching::Matcher::InvalidResponseError, "accepted #{reported.inspect}") do
        JobMatching::Matcher.new(client: client).match(resume_pdf: RESUME_PDF, job_postings: @postings)
      end
    end
  end

  test "asks Claude Haiku unless another model is configured" do
    client = bedrock_client(bedrock_response([]))

    JobMatching::Matcher.new(client: client).match(resume_pdf: RESUME_PDF, job_postings: @postings)

    assert_equal "eu.anthropic.claude-haiku-5-5", client.api_requests.first[:params][:model_id]
  end

  test "refines with the previous matches and the feedback" do
    client = bedrock_client(bedrock_response([]))
    previous = [ { "job_posting_id" => job_posting(:recent_open).id, "score" => 90 } ]

    JobMatching::Matcher.new(client: client)
      .refine(resume_pdf: RESUME_PDF, job_postings: @postings, previous_matches: previous, feedback: "Only remote jobs")

    prompt = client.api_requests.first[:params][:messages].first[:content].last[:text]
    assert_includes prompt, previous.to_json
    assert_includes prompt, "Only remote jobs"
  end

  test "describes each posting in the prompt" do
    described = prompted_postings(@postings).index_by { |posting| posting["id"] }

    assert_equal "REMOTE", described[job_posting(:recent_open).id]["work_mode"]
    assert_equal "50000-60000 EUR", described[job_posting(:recent_open).id]["salary"]
    assert_equal %w[PostgreSQL Ruby], described[job_posting(:recent_open).id]["skills"].sort
    assert_equal %w[id title company skills], described[job_posting(:old_open).id].keys
  end

  test "describes partial salaries" do
    {
      { salary_min: 50000, salary_currency: "EUR" } => "50000 EUR",
      { salary_min: 50000, salary_max: 50000, salary_currency: "EUR" } => "50000 EUR",
      { salary_min: 40000, salary_max: 50000 } => "40000-50000"
    }.each do |salary, expected|
      posting = JobPosting.new(id: "p-1", title: "Developer", **salary)

      assert_equal expected, prompted_postings([ posting ]).sole["salary"]
    end
  end

  private

  def bedrock_client(response)
    Aws::BedrockRuntime::Client.new(stub_responses: { converse: response })
  end

  def prompted_postings(postings)
    client = bedrock_client(bedrock_response([]))
    JobMatching::Matcher.new(client: client).match(resume_pdf: RESUME_PDF, job_postings: postings)
    prompt = client.api_requests.first[:params][:messages].first[:content].last[:text]
    JSON.parse(prompt[%r{<job_postings>\n(.*)\n</job_postings>}m, 1])
  end
end
