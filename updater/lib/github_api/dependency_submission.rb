# typed: strong
# frozen_string_literal: true

require "dependabot/dependency_graphers"

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

    sig { returns(Dependabot::DependencyFile) }
    attr_reader :manifest_file

    sig { returns(T::Hash[String, Dependabot::DependencyGraphers::ResolvedDependency]) }
    attr_reader :resolved_dependencies

    sig do
      params(
        job_id: String,
        branch: String,
        sha: String,
        package_manager: String,
        manifest_file: Dependabot::DependencyFile,
        resolved_dependencies: T::Hash[String, Dependabot::DependencyGraphers::ResolvedDependency]
      ).void
    end
    def initialize(job_id:, branch:, sha:, package_manager:, manifest_file:, resolved_dependencies:)
      @job_id = job_id
      @branch = branch
      @sha = sha
      @package_manager = package_manager

      @manifest_file = manifest_file
      @resolved_dependencies = resolved_dependencies
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
          resolved: resolved_dependencies.each_with_object({}) do |(name, dep), resolved|
            resolved[name] = {
              package_url: dep.package_url,
              relationship: dep.direct ? "direct" : "indirect",
              scope: dep.runtime ? "runtime" : "development",
              dependencies: dep.dependencies
            }
          end
        }
      }
    end
  end
end
