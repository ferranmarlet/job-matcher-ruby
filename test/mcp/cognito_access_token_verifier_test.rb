require "test_helper"

class CognitoAccessTokenVerifierTest < ActiveSupport::TestCase
  include CognitoTokens

  test "accepts an access token from an admin" do
    access_token = cognito_verifier.verify(cognito_access_token)

    assert_equal "user-sub", access_token.subject
    assert_equal CLIENT_ID, access_token.client_id
    assert_equal %w[openid email], access_token.scopes
  end

  test "rejects tokens it should not accept" do
    {
      "another client" => cognito_access_token(client_id: "other-client"),
      "an ID token" => cognito_access_token(token_use: "id"),
      "another issuer" => cognito_access_token(iss: "https://issuer.example.com"),
      "an expired token" => cognito_access_token(exp: 1.minute.ago.to_i),
      "a token without sub" => resign(JWT.decode(cognito_access_token, nil, false).first.except("sub")),
      "a malformed token" => "not-a-jwt"
    }.each do |case_name, token|
      assert_raises(MCP::Server::OAuth::InvalidTokenError, "accepted #{case_name}") { cognito_verifier.verify(token) }
    end
  end

  test "refuses a non-admin with insufficient scope" do
    assert_raises(MCP::Server::OAuth::InsufficientScopeError) do
      cognito_verifier.verify(cognito_access_token("cognito:groups": [ "users" ]))
    end
  end

  test "rejects a token signed with another key" do
    forged = JWT.encode(JWT.decode(cognito_access_token, nil, false).first, OpenSSL::PKey::RSA.generate(2048), "RS256", kid: JWK.kid)

    assert_raises(MCP::Server::OAuth::InvalidTokenError) { cognito_verifier.verify(forged) }
  end

  test "downloads the keys once and reuses them" do
    downloads = 0
    verifier = cognito_verifier(jwks_fetcher: -> { downloads += 1; { "keys" => [ JWK.export.deep_stringify_keys ] } })

    2.times { verifier.verify(cognito_access_token) }

    assert_equal 1, downloads
  end

  test "downloads the keys again for an unknown key after the cooldown" do
    rotated = JWT::JWK.new(OpenSSL::PKey::RSA.generate(2048), kid: "rotated-key")
    key_sets = [ [ JWK ], [ JWK, rotated ] ]
    verifier = cognito_verifier(jwks_fetcher: -> { { "keys" => key_sets.shift.map { |key| key.export.deep_stringify_keys } } })
    verifier.verify(cognito_access_token)
    token = JWT.encode(JWT.decode(cognito_access_token, nil, false).first, rotated.signing_key, "RS256", kid: "rotated-key")

    assert_raises(MCP::Server::OAuth::InvalidTokenError) { verifier.verify(token) }
    travel(CognitoAccessTokenVerifier::JWKS_REFETCH_COOLDOWN + 1.second) { verifier.verify(token) }
  end

  private

  def resign(claims)
    JWT.encode(claims, SIGNING_KEY, "RS256", kid: JWK.kid)
  end
end
