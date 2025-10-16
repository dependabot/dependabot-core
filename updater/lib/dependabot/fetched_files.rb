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

    sig { params(dependency_files: T::Array[Dependabot::DependencyFile], base_commit_sha: String).void }
    def initialize(dependency_files:, base_commit_sha:)
      @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
      @base_commit_sha = T.let(base_commit_sha, String)
    end
  end
end
