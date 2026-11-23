module JobMatching
  UserMatches = Data.define(:user, :matches, :error, :skipped_reason) do
    def self.matched(user, matches)
      new(user: user, matches: matches, error: nil, skipped_reason: nil)
    end

    def self.failed(user, error)
      new(user: user, matches: [], error: error, skipped_reason: nil)
    end

    def self.skipped(user, reason)
      new(user: user, matches: [], error: nil, skipped_reason: reason)
    end

    def failed?
      !error.nil?
    end

    def as_json(*)
      {
        user_id: user.id,
        user_email: user.email,
        matches: matches.map(&:as_json),
        error: error,
        skipped: skipped_reason
      }.compact.as_json
    end
  end
end
