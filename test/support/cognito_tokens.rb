module CognitoTokens
  ISSUER = "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_test"
  CLIENT_ID = "spa-client"
  SIGNING_KEY = OpenSSL::PKey::RSA.generate(2048)
  JWK = JWT::JWK.new(SIGNING_KEY, kid: "test-key")

  def cognito_verifier(jwks_fetcher: -> { { "keys" => [ JWK.export.deep_stringify_keys ] } })
    CognitoAccessTokenVerifier.new(issuer: ISSUER, client_id: CLIENT_ID, jwks_fetcher: jwks_fetcher)
  end

  def cognito_access_token(**overrides)
    claims = {
      iss: ISSUER,
      sub: "user-sub",
      client_id: CLIENT_ID,
      token_use: "access",
      scope: "openid email",
      "cognito:groups": [ "admin" ],
      exp: 1.hour.from_now.to_i
    }.merge(overrides)

    JWT.encode(claims, SIGNING_KEY, "RS256", kid: JWK.kid)
  end
end
