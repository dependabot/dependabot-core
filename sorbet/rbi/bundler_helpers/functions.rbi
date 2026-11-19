# typed: strict
# frozen_string_literal: true

# Public APIs common to the v2 and v4 helper implementations.
module Functions
  sig do
    params(
      dir: T.nilable(T.any(String, Pathname)),
      gemfile_name: String,
      credentials: T.any(T::Array[T::Hash[String, String]], T::Hash[String, String])
    ).returns(T.nilable(String))
  end
  def self.jfrog_source(dir:, gemfile_name:, credentials:); end

  sig do
    params(
      dir: T.nilable(T.any(String, Pathname)),
      gemfile_name: String,
      credentials: T.any(T::Array[T::Hash[String, String]], T::Hash[String, String])
    ).returns(T::Array[T::Hash[Symbol, String]])
  end
  def self.git_specs(dir:, gemfile_name:, credentials:); end

  class FileParser
    sig { params(lockfile_name: T.nilable(String)).void }
    def initialize(lockfile_name:); end

    sig { params(gemfile_name: String).returns(T::Array[T::Hash[Symbol, T.anything]]) }
    def parsed_gemfile(gemfile_name:); end

    sig { params(gemspec_name: String).returns(T::Array[T::Hash[Symbol, T.anything]]) }
    def parsed_gemspec(gemspec_name:); end
  end

  class DependencySource
    sig { params(gemfile_name: String, dependency_name: String).void }
    def initialize(gemfile_name:, dependency_name:); end

    sig { returns(T::Array[Gem::Version]) }
    def private_registry_versions; end
  end

  class ForceUpdater
    sig do
      params(
        dependency_name: String,
        target_version: String,
        gemfile_name: String,
        lockfile_name: T.nilable(String),
        update_multiple_dependencies: T::Boolean
      ).void
    end
    def initialize(dependency_name:, target_version:, gemfile_name:, lockfile_name:, update_multiple_dependencies:); end

    sig { returns(T::Array[T::Array[T::Hash[Symbol, T.any(String, Gem::Version)]]]) }
    def run; end
  end

  class VersionResolver
    sig do
      params(
        dependency_name: String,
        dependency_requirements: T::Array[T::Hash[Symbol, T.anything]],
        gemfile_name: String,
        lockfile_name: T.nilable(String)
      ).void
    end
    def initialize(dependency_name:, dependency_requirements:, gemfile_name:, lockfile_name:); end

    sig { returns(T.nilable(T.any(String, T::Hash[Symbol, T.anything]))) }
    def version_details; end
  end

  class ConflictingDependencyResolver
    sig { params(dependency_name: String, target_version: String, lockfile_name: String).void }
    def initialize(dependency_name:, target_version:, lockfile_name:); end

    sig { returns(T::Array[T::Hash[String, String]]) }
    def conflicting_dependencies; end
  end
end
