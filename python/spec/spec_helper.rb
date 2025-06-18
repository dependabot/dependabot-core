# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

sig { returns(String) }
def common_dir
  @common_dir ||= T.let(Gem::Specification.find_by_name("dependabot-common").gem_dir, T.nilable(String))
end

sig { params(path: String).void }
def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

module SlowTestHelper
  extend T::Sig

  sig { returns(T::Boolean) }
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

  config.profile_examples = 10
end
