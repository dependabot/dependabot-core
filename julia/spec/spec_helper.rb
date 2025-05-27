# typed: false
# frozen_string_literal: true

require "rspec"
require "webmock/rspec"
require "vcr"

require "dependabot/julia"
require_relative "dependabot/shared_examples"

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

RSpec.configure do |config|
  config.include WebMock::API

  config.before(:suite) do
    WebMock.enable!
  end

  config.before do
    # Stub Julia registry
    stub_request(:get, %r{github.com\/JuliaRegistries\/General})
      .to_return(
        status: 200,
        body: fixture("registry_responses", "General.toml")
      )
  end
end

def fixture(*args)
  File.read(
    File.join("spec", "fixtures", *args)
  )
end
