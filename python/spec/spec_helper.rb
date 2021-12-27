# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

module SlowTestHelper
  def self.slow_tests?
    ENV["SUITE_NAME"] == "python_slow"
  end
end

RSpec.configure do |config|
  config.around do |example|
    if SlowTestHelper.slow_tests? && example.metadata[:slow]
      example.run
    elsif !SlowTestHelper.slow_tests? && !example.metadata[:slow]
      example.run
    else
      example.skip
    end
  end
end
