Aws.config.update(stub_responses: true, region: "eu-west-1")
ENV["RESUMES_BUCKET_NAME"] ||= "resumes-test"

module AwsStubs
  RESUME_PDF = "%PDF-1.7 resume".b

  def teardown
    Aws.config.delete(:s3)
    Aws.config.delete(:bedrockruntime)
    super
  end

  def bedrock_response(matches, stop_reason: "tool_use")
    {
      output: {
        message: {
          role: "assistant",
          content: [ { tool_use: { tool_use_id: "tool-1", name: JobMatching::Matcher::TOOL_NAME, input: { "matches" => matches } } } ]
        }
      },
      stop_reason: stop_reason,
      usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 },
      metrics: { latency_ms: 1 }
    }
  end

  def stub_aws_matching(matches)
    Aws.config[:s3] = { stub_responses: { head_object: { content_length: RESUME_PDF.bytesize }, get_object: { body: RESUME_PDF } } }
    Aws.config[:bedrockruntime] = { stub_responses: { converse: bedrock_response(matches) } }
  end
end
