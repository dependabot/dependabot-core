# typed: strong
# frozen_string_literal: true

require "dependabot/dependency_graphers"
require "dependabot/environment"
require "github_api/ecosystem_mapper"

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

    # Expected reasons for empty or degraded snapshots
    DEGRADED_REASON_SUBDEPENDENCY_ERR = "error fetching sub-dependencies"
    EMPTY_REASON_NO_MANIFESTS = "missing manifest files"

    class SnapshotStatus < T::Enum
      enums do
        SUCCESS = new("ok")
        DEGRADED = new("degraded")
        SKIPPED = new("skipped")
        FAILED = new("failed")
      end
    end

    sig { returns(String) }
    attr_reader :job_id

    sig { returns(String) }
    attr_reader :branch

    sig { returns(String) }
    attr_reader :sha

    sig { returns(String) }
    attr_reader :package_manager

    sig { returns(T::Array[Dependabot::DependencyGraphers::ManifestGroupSnapshot]) }
    attr_reader :manifest_snapshots

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
        manifest_snapshots: T::Array[Dependabot::DependencyGraphers::ManifestGroupSnapshot],
        status: SnapshotStatus,
        reason: T.nilable(String)
      ).void
    end
    def initialize(
      job_id:,
      branch:,
      sha:,
      package_manager:,
      manifest_snapshots:,
      status: SnapshotStatus::SUCCESS,
      reason: nil
    )
      @job_id = job_id
      @branch = branch
      @sha = sha
      @package_manager = package_manager

      # A submission always covers a single directory, and every ecosystem produces at least one manifest
      # group snapshot, even in the case of
      raise ArgumentError, "manifest_snapshots must not be empty" if manifest_snapshots.empty?

      @manifest_snapshots = manifest_snapshots

      @status = status
      @reason = reason
    end

    # The representative manifest file for the submission, used for the job correlator and scanned path. All
    # snapshots share a directory, so any of them yields the same correlator; we use the first.
    sig { returns(Dependabot::DependencyFile) }
    def manifest_file
      T.must(@manifest_snapshots.first).manifest_file
    end

    # The aggregate resolved dependency set across every manifest in the submission. Used for logging and
    # empty-submission checks; the payload itself is built per-manifest from `manifest_snapshots`.
    sig { returns(T::Hash[String, Dependabot::DependencyGraphers::ResolvedDependency]) }
    def resolved_dependencies
      @manifest_snapshots.each_with_object({}) do |snapshot, aggregate|
        aggregate.merge!(snapshot.resolved_dependencies)
      end
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
        # TODO: Move use of metadata to a Dependabot-specific object
        #
        # We are using the existing job metadata as a bag-of-values for error handling
        # and job tracking that is specific to Dependabot-created submissions.
        #
        # In future, we should extend the public API schema with a validated object to
        # harden this contract.
        metadata: {
          status: status.serialize,
          reason: reason,
          scanned_manifest_path: scanned_manifest_path
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
      @manifest_snapshots.each_with_object({}) do |snapshot, manifests|
        entry = manifest_entry(snapshot)
        next if entry.nil?

        manifests[snapshot.manifest_file.path] = entry
      end
    end

    # Builds a single manifest entry for the payload, or nil when there is no real manifest file to report
    # (e.g. an empty submission representing a directory where no manifests were found or a failure occurred).
    #
    # A manifest file that genuinely resolves to no dependencies is still emitted with an empty `resolved`
    # collection so the snapshot reflects that the file was scanned.
    sig do
      params(snapshot: Dependabot::DependencyGraphers::ManifestGroupSnapshot)
        .returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def manifest_entry(snapshot)
      manifest_file = snapshot.manifest_file
      return nil if manifest_file.name.empty?

      {
        name: manifest_file.path,
        file: {
          source_location: manifest_file.path.gsub(%r{^/}, "")
        },
        metadata: {
          ecosystem: GithubApi::EcosystemMapper.ecosystem_for(package_manager),
          blob_oid: manifest_file.blob_oid(algorithm: blob_hash_algorithm)
        }.compact,
        resolved: snapshot.resolved_dependencies.transform_values do |resolved|
          {
            package_url: resolved.package_url,
            relationship: resolved.direct ? "direct" : "indirect",
            scope: resolved.runtime ? "runtime" : "development",
            dependencies: resolved.dependencies
          }
        end
      }
    end

    # Returns a synopsis of the scan performed in the format `ecosystem::manifest_path`, e.g.
    # - `golang::/`
    # - `rubygems::/rails_app/`
    #
    sig do
      returns(String)
    end
    def scanned_manifest_path
      "#{GithubApi::EcosystemMapper.ecosystem_for(package_manager)}::#{manifest_file.directory}"
    end

    # Infers the repository's Git object format from the commit SHA length.
    # SHA-1 produces 40 hex chars, SHA-256 produces 64.
    sig { returns(Symbol) }
    def blob_hash_algorithm
      sha.length >= 64 ? :sha256 : :sha1
    end
  end
end
