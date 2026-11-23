module JobMatching
  class ResumeStorage
    class UnusableResumeError < StandardError; end

    MAX_BYTES = 4_500_000
    PDF_SIGNATURE = "%PDF-".b

    def initialize(client: Aws::S3::Client.new, bucket: ENV.fetch("RESUMES_BUCKET_NAME"))
      @client = client
      @bucket = bucket
    end

    def download(resume)
      size = @client.head_object(bucket: @bucket, key: resume.file_link).content_length
      raise UnusableResumeError, "Resume #{resume.id} is larger than #{MAX_BYTES} bytes" if size > MAX_BYTES

      pdf = @client.get_object(bucket: @bucket, key: resume.file_link).body.read
      raise UnusableResumeError, "Resume #{resume.id} is not a PDF" unless pdf.b.start_with?(PDF_SIGNATURE)

      pdf
    end
  end
end
