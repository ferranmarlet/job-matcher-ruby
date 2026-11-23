require "test_helper"

class JobPostingTest < ActiveSupport::TestCase
  test "selects open postings discovered since a time" do
    assert_equal [ job_posting(:recent_open) ], JobPosting.currently_open.discovered_since(1.week.ago).to_a
  end

  test "cannot be written, because jobscan owns the table" do
    assert_raises(ActiveRecord::ReadOnlyRecord) { job_posting(:recent_open).update!(title: "Changed") }
  end
end
