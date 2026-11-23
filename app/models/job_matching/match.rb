module JobMatching
  Match = Data.define(:job_posting, :score, :reasons, :gaps) do
    def as_json(*)
      {
        job_posting_id: job_posting.id,
        title: job_posting.title,
        company: job_posting.company,
        source_url: job_posting.source_url,
        score: score,
        reasons: reasons,
        gaps: gaps
      }
    end
  end
end
