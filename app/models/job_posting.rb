class JobPosting < ApplicationRecord
  self.table_name = "job_posting"

  OPEN_STATUS = "OPEN"

  has_many :skills, class_name: "JobPostingSkill"

  scope :currently_open, -> { where(status: OPEN_STATUS) }
  scope :discovered_since, ->(time) { where(discovered_at: time..) }
end
