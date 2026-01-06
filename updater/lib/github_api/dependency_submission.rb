# typed: strong
# frozen_string_literal: true

require "dependabot/dependency_graphers"
require "dependabot/environment"

# This class provides a data object that can be submitted to a repository's dependency submission
# REST API.
#
# See:
#   https://docs.github.com/en/rest/dependency-graph/dependency-submission
module GithubApi
  class DependencySubmission
    extend T::Sig

    SNAPSHOT_VERSION = 1
    SNAPSHOT_DETECTOR_NAME = "dependabot"
    SNAPSHOT_DETECTOR_URL = "https://github.com/dependabot/dependabot-core"

    class SnapshotStatus < T::Enum
      enums do
        SUCCESS = new("ok")
        FAILED = new("failed")
        SKIPPED = new("skipped")
      end
    end

    # Expected when the graph change corresponds to a deleted manifest file
    SNAPSHOT_REASON_NO_MANIFESTS = "missing-manifest-files"

    sig { returns(String) }
    attr_reader :job_id

    sig { returns(String) }
    attr_reader :branch

    sig { returns(String) }
    attr_reader :sha

    sig { returns(String) }
    attr_reader :package_manager

    sig { returns(Dependabot::DependencyFile) }
    attr_reader :manifest_file

    sig { returns(T::Hash[String, Dependabot::DependencyGraphers::ResolvedDependency]) }
    attr_reader :resolved_dependencies

    sig { returns(SnapshotStatus) }
    attr_reader :status

    sig { returns(T.nilable(String)) }
    attr_reader :reason

    sig do
      params(
        job_id: String,
        branch: String,
        sha: String,
        package_manager: String,
        manifest_file: Dependabot::DependencyFile,
        resolved_dependencies: T::Hash[String, Dependabot::DependencyGraphers::ResolvedDependency],
        status: SnapshotStatus,
        reason: T.nilable(String)
      ).void
    end
    def initialize(
      job_id:,
      branch:,
      sha:,
      package_manager:,
      manifest_file:,
      resolved_dependencies:,
      status: SnapshotStatus::SUCCESS,
      reason: nil
    )
      @job_id = job_id
      @branch = branch
      @sha = sha
      @package_manager = package_manager

      @manifest_file = manifest_file
      @resolved_dependencies = resolved_dependencies

      @status = status
      @reason = reason
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
          version: detector_version,
          url: SNAPSHOT_DETECTOR_URL
        },
        manifests: manifests,
        metadata: {
          status: status.serialize,
          reason: reason
        }.compact
      }
    end

    private

    sig { returns(String) }
    def job_correlator
      base = "#{SNAPSHOT_DETECTOR_NAME}-#{package_manager}"

      # If the manifest file does not have a name (e.g.,
      # it is an empty file representing a deleted manifest),
      # `path` will refer to the directory instead of a file.
      path = manifest_file.path
      dirname = manifest_file.name.empty? ? path : File.dirname(path)
      dirname = dirname.gsub(%r{^/}, "")

      sanitized_path = if dirname.bytesize > 32
                         # If the dirname is pathologically long, we replace it with a SHA256
                         Digest::SHA256.hexdigest(dirname)
                       else
                         dirname.tr("/", "-")
                       end

      sanitized_path.empty? ? base : "#{base}-#{sanitized_path}"
    end

    sig { returns(String) }
    def detector_version
      [
        Dependabot::VERSION,
        Dependabot::Environment.updater_sha
      ].compact.join("-")
    end

    sig { returns(String) }
    def symbolic_ref
      return branch.gsub(%r{^/}, "") if branch.start_with?(%r{/?ref})

      "refs/heads/#{branch}"
    end

    sig do
      returns(T::Hash[String, T.untyped])
    end
    def manifests
      return {} if resolved_dependencies.empty?

      {
        manifest_file.path => {
          name: manifest_file.path,
          file: {
            source_location: manifest_file.path.gsub(%r{^/}, "")
          },
          metadata: {
            ecosystem: package_manager
          },
          resolved: resolved_dependencies.transform_values do |resolved|
            {
              package_url: resolved.package_url,
              relationship: resolved.direct ? "direct" : "indirect",
              scope: resolved.runtime ? "runtime" : "development",
              dependencies: resolved.dependencies
            }
          end
        }
      }
    end
  end
end
