class JobPostingSkill < ApplicationRecord
  self.table_name = "job_posting_skill"
  self.primary_key = [ :job_posting_id, :skill ]

  belongs_to :job_posting
end
