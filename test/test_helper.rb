ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/jobscan_schema"
require_relative "support/aws_stubs"
require_relative "support/cognito_tokens"

JobscanSchema.load!

module ActiveSupport
  class TestCase
    include AwsStubs

    fixtures :all
  end
end
