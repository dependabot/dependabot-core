# typed: true
# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

RSpec.configure do |config|
  config.before(:suite) do
    ENV["COMPOSER_HOME"] = "tmp/test-home-#{ENV['TEST_ENV_NUMBER']}" if ENV["TEST_ENV_NUMBER"]
  end

  config.profile_examples = 10
end
