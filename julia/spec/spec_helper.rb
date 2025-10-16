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
    # NOTE: Julia's registry is locally cached and accessed via Pkg through DependabotHelper.jl.
    # Tests use real registry calls for integration tests and mocks for unit tests as appropriate.
  end
end

def fixture(*args)
  File.read(
    File.join("spec", "fixtures", *args)
  )
end
