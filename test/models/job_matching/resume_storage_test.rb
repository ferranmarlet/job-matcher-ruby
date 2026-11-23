require "test_helper"

class JobMatching::ResumeStorageTest < ActiveSupport::TestCase
  test "downloads the resume from its key in the bucket" do
    client = s3_client(body: RESUME_PDF)

    pdf = JobMatching::ResumeStorage.new(client: client, bucket: "resumes").download(resumes(:alice))

    assert_equal RESUME_PDF, pdf
    assert_equal({ bucket: "resumes", key: "resumes/alice.pdf" }, client.api_requests.last[:params].slice(:bucket, :key))
  end

  test "refuses files that are not PDFs" do
    client = s3_client(body: "PK\x03\x04 a docx file")

    assert_raises(JobMatching::ResumeStorage::UnusableResumeError) do
      JobMatching::ResumeStorage.new(client: client, bucket: "resumes").download(resumes(:alice))
    end
  end

  test "refuses files larger than Bedrock accepts, without downloading them" do
    client = s3_client(body: RESUME_PDF, size: JobMatching::ResumeStorage::MAX_BYTES + 1)

    assert_raises(JobMatching::ResumeStorage::UnusableResumeError) do
      JobMatching::ResumeStorage.new(client: client, bucket: "resumes").download(resumes(:alice))
    end
    assert_equal [ :head_object ], client.api_requests.map { |request| request[:operation_name] }
  end

  private

  def s3_client(body:, size: body.bytesize)
    Aws::S3::Client.new(stub_responses: { head_object: { content_length: size }, get_object: { body: body } })
  end
end
