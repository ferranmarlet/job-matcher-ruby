class CognitoAccessTokenVerifier < MCP::Server::OAuth::TokenVerifier
  REQUIRED_GROUP = "admin"
  JWKS_REFETCH_COOLDOWN = 5.minutes
  JWKS_TIMEOUT_SECONDS = 5

  def initialize(issuer:, client_id:, jwks_fetcher: nil)
    super()
    @issuer = issuer
    @client_id = client_id
    @jwks_fetcher = jwks_fetcher || -> { download_jwks }
    @mutex = Mutex.new
  end

  def verify(token)
    claims, = JWT.decode(token, nil, true,
      algorithms: [ "RS256" ], iss: @issuer, verify_iss: true, required_claims: %w[exp sub], jwks: method(:jwks))
    raise MCP::Server::OAuth::InvalidTokenError, "Invalid token" unless issued_to_this_client?(claims)
    raise MCP::Server::OAuth::InsufficientScopeError, "Requires the #{REQUIRED_GROUP} group" unless in_required_group?(claims)

    MCP::Server::OAuth::AccessToken.new(
      token: token,
      client_id: @client_id,
      scopes: claims["scope"].to_s.split,
      expires_at: claims["exp"],
      subject: claims["sub"],
      issuer: @issuer,
      claims: claims
    )
  rescue JWT::DecodeError
    raise MCP::Server::OAuth::InvalidTokenError, "Invalid token"
  end

  private

  def issued_to_this_client?(claims)
    claims["token_use"] == "access" && claims["client_id"] == @client_id
  end

  def in_required_group?(claims)
    Array(claims["cognito:groups"]).include?(REQUIRED_GROUP)
  end

  def jwks(options = {})
    @mutex.synchronize do
      @jwks = nil if options[:kid_not_found] && @jwks_fetched_at&.before?(JWKS_REFETCH_COOLDOWN.ago)
      @jwks ||= @jwks_fetcher.call.tap { @jwks_fetched_at = Time.current }
    end
  end

  def download_jwks
    uri = URI("#{@issuer}/.well-known/jwks.json")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
      open_timeout: JWKS_TIMEOUT_SECONDS, read_timeout: JWKS_TIMEOUT_SECONDS) { |http| http.get(uri.path) }
    response.value
    JSON.parse(response.body)
  end
end
