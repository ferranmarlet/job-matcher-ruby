module RdsIamAuthentication
  def self.auth_token(host:, port:, user:)
    token_generator.auth_token(
      region: ENV.fetch("AWS_REGION"),
      endpoint: "#{host}:#{port}",
      user_name: user
    )
  end

  def self.token_generator
    @token_generator ||= Aws::RDS::AuthTokenGenerator.new(
      credentials: Aws::RDS::Client.new(region: ENV.fetch("AWS_REGION")).config.credentials
    )
  end

  module FreshTokenPerConnection
    def new_client(conn_params)
      token = RdsIamAuthentication.auth_token(**conn_params.slice(:host, :port, :user))
      super(conn_params.merge(password: token))
    end
  end
end

if ENV["DB_IAM_AUTH"] == "true"
  ActiveSupport.on_load(:active_record_postgresqladapter) do
    singleton_class.prepend(RdsIamAuthentication::FreshTokenPerConnection)
  end
end
