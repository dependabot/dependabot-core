# typed: false
# frozen_string_literal: true

# Sorbet cannot type the variadic Open3 call or rewrite this shared context's around hook.

require "sorbet-runtime"

extend T::Sig # rubocop:disable Style/MixinUsage

sig { returns(String) }
def common_dir
  @common_dir ||= T.let(Gem::Specification.find_by_name("dependabot-common").gem_dir, T.nilable(String))
end

sig { params(path: String).returns(T::Boolean) }
def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

sig { params(args: T::Array[String], dir: String).returns(String) }
def run_git(args, dir)
  stdout, stderr, status = Open3.capture3(
    {
      "GIT_AUTHOR_NAME" => "Pub Test",
      "GIT_AUTHOR_EMAIL" => "pub@dartlang.org",
      "GIT_COMMITTER_NAME" => "Pub Test",
      "GIT_COMMITTER_EMAIL" => "pub@dartlang.org",
      # To make stable commits ids we fix the date.
      "GIT_COMMITTER_DATE" => "1970-01-01T00:00:00.000",
      "GIT_AUTHOR_DATE" => "1970-01-01T00:00:00.000"
    },
    "git",
    *args,
    chdir: dir
  )
  raise "git #{args.join(' ')} failed `#{stdout}` `#{stderr}`" if status != 0

  stdout
end

RSpec.shared_context "with temp dir" do
  around do |example|
    Dir.mktmpdir("rspec-") do |dir|
      @temp_dir = dir
      example.run
    end
  end

  attr_reader :temp_dir
end

require "#{common_dir}/spec/spec_helper.rb"
