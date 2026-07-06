# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class FetchedFiles
    extend T::Sig

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    attr_reader :dependency_files

    sig { returns(String) }
    attr_reader :base_commit_sha

    # Maps a directory to the non-fatal fetch error encountered while fetching it
    # (e.g. an unresolvable path dependency for a graph job). The directory is
    # still reported, but with a degraded snapshot describing the failure.
    sig { returns(T::Hash[String, Dependabot::DependabotError]) }
    attr_reader :directory_fetch_errors

    sig do
      params(
        dependency_files: T::Array[Dependabot::DependencyFile],
        base_commit_sha: String,
        directory_fetch_errors: T::Hash[String, Dependabot::DependabotError]
      ).void
    end
    def initialize(dependency_files:, base_commit_sha:, directory_fetch_errors: {})
      @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
      @base_commit_sha = T.let(base_commit_sha, String)
      @directory_fetch_errors = T.let(
        directory_fetch_errors,
        T::Hash[String, Dependabot::DependabotError]
      )
    end
  end
end
