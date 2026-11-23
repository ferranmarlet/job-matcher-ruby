class User < ApplicationRecord
  has_one :resume

  scope :with_auto_analysis, -> { where(auto_analysis_enabled: true) }
end
