# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

extend T::Sig # rubocop:disable Style/MixinUsage

sig { returns(String) }
def common_dir
  @common_dir ||= T.let(Gem::Specification.find_by_name("dependabot-common").gem_dir, T.nilable(String))
end

sig { params(path: String).void }
def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"
