# typed: false
# frozen_string_literal: true

require "open3"
require "rbconfig"
require "spec_helper"
require "dependabot/clients/json_response_parser"

RSpec.describe Dependabot::Clients::JsonResponseParser do
  it "loads and parses JSON without another client loading JSON first" do
    lib_path = File.expand_path("../../../lib", __dir__)
    script = <<~RUBY
      require "dependabot/clients/json_response_parser"

      parser = Class.new do
        include Dependabot::Clients::JsonResponseParser

        def parse
          parse_json_object("{}", "test")
        end

        def response_identity
          ["test", "https://example.com"]
        end
      end

      parser.new.parse
    RUBY

    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", lib_path, "-e", script)

    expect(stderr).to eq("")
    expect(status).to be_success
  end
end
