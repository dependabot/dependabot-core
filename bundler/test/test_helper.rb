# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

extend T::Sig

sig { returns(String) }
def common_dir
  Gem::Specification.find_by_name("dependabot-common").gem_dir
end

sig { params(path: String).void }
def require_common_test(path)
  require "#{common_dir}/test/dependabot/#{path}"
end

require "#{common_dir}/test/test_helper.rb"

# Base test class for bundler tests
class BundlerTestCase < DependabotTestCase
  extend T::Sig

  # Bundler-specific helper methods
  sig { params(project_name: String, directory: String).returns(T::Array[Dependabot::DependencyFile]) }
  def bundler_project_dependency_files(project_name, directory: "/")
    project_dependency_files(project_name, directory: directory)
  end

  sig { returns(Dependabot::Source) }
  def bundler_source
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot/dependabot-core",
      directory: "/"
    )
  end

  sig do
    params(gemfile_fixture_name: String,
           lockfile_fixture_name: T.nilable(String)).returns(T::Array[Dependabot::DependencyFile])
  end
  def bundler_dependency_files(gemfile_fixture_name, lockfile_fixture_name = nil)
    files = [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("bundler/gemfiles/#{gemfile_fixture_name}")
      )
    ]

    if lockfile_fixture_name
      files << Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler/lockfiles/#{lockfile_fixture_name}")
      )
    end

    files
  end

  sig { returns(T::Hash[String, String]) }
  def bundler_credentials
    {
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }
  end
end
