module JobMatcherMcp
  TOOLS = [ MatchJobsTool, RefineMatchesTool ].freeze

  class << self
    def transport
      @transport ||= MCP::Server::Transports::StreamableHTTPTransport.new(
        MCP::Server.new(name: "job_matcher", version: "1.0.0", tools: TOOLS),
        stateless: true,
        enable_json_response: true,
        serve_subscriptions_listen: false,
        token_verifier: token_verifier
      )
    end

    def token_verifier
      @token_verifier ||= CognitoAccessTokenVerifier.new(
        issuer: ENV.fetch("COGNITO_ISSUER_URI"),
        client_id: ENV.fetch("COGNITO_SPA_CLIENT_ID")
      )
    end

    def token_verifier=(verifier)
      @token_verifier = verifier
      @transport = nil
    end
  end
end
