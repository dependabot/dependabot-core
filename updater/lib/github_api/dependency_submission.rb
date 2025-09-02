# typed: strong
# frozen_string_literal: true

require "dependabot/dependency_grapher"

# This class provides a data object that can be submitted to a repository's dependency submission
# REST API.
#
# See:
#   https://docs.github.com/en/rest/dependency-graph/dependency-submission
module GithubApi
  class DependencySubmission
    extend T::Sig

    SNAPSHOT_VERSION = 0
    SNAPSHOT_DETECTOR_NAME = "dependabot"
    SNAPSHOT_DETECTOR_URL = "https://github.com/dependabot/dependabot-core"

    sig { returns(String) }
    attr_reader :job_id
    sig { returns(String) }
    attr_reader :branch
    sig { returns(String) }
    attr_reader :sha
    sig { returns(String) }
    attr_reader :package_manager
    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :manifests

    sig do
      params(
        job_id: String,
        branch: String,
        sha: String,
        ecosystem: Dependabot::Ecosystem,
        dependency_files: T::Array[Dependabot::DependencyFile],
        dependencies: T::Array[Dependabot::Dependency]
      ).void
    end
    def initialize(job_id:, branch:, sha:, ecosystem:, dependency_files:, dependencies:)
      @job_id = job_id
      @branch = branch
      @sha = sha
      @package_manager = T.let(ecosystem.name, String)

      @manifests = T.let(build_manifests(dependency_files, dependencies), T::Hash[String, T.untyped])
    end

    # TODO: Change to a typed structure?
    #
    # See: https://sorbet.org/docs/tstruct
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def payload
      {
        version: SNAPSHOT_VERSION,
        sha: sha,
        ref: symbolic_ref,
        job: {
          correlator: job_correlator,
          id: job_id
        },
        detector: {
          name: SNAPSHOT_DETECTOR_NAME,
          version: Dependabot::VERSION,
          url: SNAPSHOT_DETECTOR_URL
        },
        manifests: manifests
      }
    end

    private

    sig { returns(String) }
    def job_correlator
      "#{SNAPSHOT_DETECTOR_NAME}-#{package_manager}"
    end

    sig { returns(String) }
    def symbolic_ref
      return branch.gsub(%r{^/}, "") if branch.start_with?(%r{/?ref})

      "refs/heads/#{branch}"
    end

    sig do
      params(
        dependency_files: T::Array[Dependabot::DependencyFile],
        dependencies: T::Array[Dependabot::Dependency]
      ).returns(T::Hash[String, T.untyped])
    end
    def build_manifests(dependency_files, dependencies)
      return {} if dependencies.empty?

      grapher = Dependabot::DependencyGrapher.for_package_manager(package_manager).new(
        dependency_files: dependency_files,
        dependencies: dependencies
      )

      file = grapher.relevant_dependency_file

      {
        file.path => {
          name: file.path,
          file: {
            source_location: file.path.gsub(%r{^/}, "")
          },
          metadata: {
            ecosystem: package_manager
          },
          resolved: grapher.resolved_dependencies.to_h
        }
      }
    end
  end
end
