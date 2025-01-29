# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

extend T::Sig

sig { returns(String) }
def common_dir
  @common_dir = T.let(@common_dir, T.nilable(String))
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

sig { params(path: String).void }
def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"
