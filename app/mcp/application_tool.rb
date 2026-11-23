class ApplicationTool < MCP::Tool
  SINCE_PROPERTY = {
    type: "string",
    format: "date",
    description: "Only job postings discovered on or after this date (YYYY-MM-DD). Defaults to a week ago."
  }.freeze

  class << self
    private

    def json_response(payload, note: nil)
      content = [ { type: "text", text: JSON.pretty_generate(payload) } ]
      content << { type: "text", text: note } if note
      MCP::Tool::Response.new(content)
    end

    def error_response(message)
      MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
    end

    def parse_date(value)
      value.presence && Date.iso8601(value)
    end

    def reporting_input_errors(user_email)
      yield
    rescue ActiveRecord::RecordNotFound
      error_response("No user has the email #{user_email}")
    rescue Date::Error
      error_response("since must be a date formatted as YYYY-MM-DD")
    end
  end
end
