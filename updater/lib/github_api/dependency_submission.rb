# typed: strict
# frozen_string_literal: true

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
    attr_reader :directory
    sig { returns(String) }
    attr_reader :package_manager
    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :manifests

    sig { params(job: Dependabot::Job, snapshot: Dependabot::DependencySnapshot).void }
    def initialize(job:, snapshot:)
      @job_id = T.let(job.id.to_s, String)
      # TODO: Ensure that the branch is always set for analysis runs
      #
      # For purposes of the POC, we'll assume the default branch of `main`
      # if this is nil, but this isn't a sustainable approach
      @branch = T.let(job.source.branch || "main", String)
      @sha = T.let(snapshot.base_commit_sha, String)
      # TODO: Ensure that directory is always set for analysis runs
      #
      # We shouldn't need to default here, this is mostly for type safety
      # but we should make sure this value is set as we proceed
      @directory = T.let(job.source.directory || "/", String)
      @package_manager = T.let(job.package_manager, String)

      @manifests = T.let(build_manifests(snapshot), T::Hash[String, T.untyped])
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
        scanned: scanned,
        manifests: manifests
      }
    end

    private

    sig { returns(String) }
    def job_correlator
      "#{SNAPSHOT_DETECTOR_NAME}-experimental"
    end

    sig { returns(String) }
    def scanned
      Time.now.utc.iso8601
    end

    sig { returns(String) }
    def symbolic_ref
      return branch.gsub(%r{^/}, "") if branch.start_with?(%r{/?ref})

      "refs/heads/#{branch}"
    end

    sig { params(snapshot: Dependabot::DependencySnapshot).returns(T::Hash[String, T.untyped]) }
    def build_manifests(snapshot)
      dependencies_by_manifest = {}
      relevant_manifests(snapshot).each do |file|
        dependencies_by_manifest[file.path] ||= []
        file.dependencies.each do |dependency|
          dependencies_by_manifest[file.path] << dependency
        end
      end

      dependencies_by_manifest.each_with_object({}) do |(file, deps), manifests|
        # TODO: Confirm whether this approach will work properly with multi-directory job definitions
        #
        # For now it is tolerable to omit this and limit our testing accordingly, but we
        # should behave sensibly in a multi-directory context as well

        # source location is relative to the root of the repo, so we strip the leading slash
        source_location = file.gsub(%r{^/}, "")

        manifests[file] = {
          name: file,
          file: {
            source_location: source_location
          },
          metadata: {
            ecosystem: T.must(snapshot.ecosystem).name
          },
          resolved: deps.uniq.each_with_object({}) do |dep, resolved|
            resolved[dep.name] = {
              package_url: build_purl(dep),
              relationship: relationship_for(dep),
              scope: scope_for(dep),
              dependencies: dep.metadata.fetch(:depends_on, []),
              metadata: {}
            }
          end
        }
      end
    end

    # For each distinct directory in our manifest list, we only want the highest precedent manifests available,
    # this method will filter out manifests for directories that have lockfiles and so on.
    sig { params(snapshot: Dependabot::DependencySnapshot).returns(T::Array[Dependabot::DependencyFile]) }
    def relevant_manifests(snapshot)
      manifests_by_directory = snapshot.dependency_files.each_with_object({}) do |file, dirs|
        # Build up a dictionary of unique directories...
        dirs[file.directory] ||= {}
        # Add a list of files for each distinct precedence...
        dirs[file.directory][file.precedence] ||= []
        dirs[file.directory][file.precedence] << file
      end

      manifests_by_directory.map do |_directory, manifests_by_precedence|
        # ... and cherry pick the highest precedence list for each directory
        manifests_by_precedence[manifests_by_precedence.keys.max]
      end.flatten
    end

    # Helper function to create a Package URL (purl)
    #
    # TODO: Move out of this class.
    #
    # It probably makes more sense to assign this to a Dependabot::Dependency
    # when it is created so the ecosystem-specific parser can own this?
    #
    # Let's let it live here for now until we start making changes to core to
    # fill in some blanks.
    sig { params(dependency: Dependabot::Dependency).returns(String) }
    def build_purl(dependency)
      "pkg:#{purl_pkg_for(dependency.package_manager)}/#{dependency.name}@#{dependency.version}"
    end

    sig { params(package_manager: String).returns(String) }
    def purl_pkg_for(package_manager)
      case package_manager
      when "bundler"
        "gem"
      when "npm_and_yarn", "bun"
        "npm"
      when "maven", "gradle"
        "maven"
      when "pip", "uv"
        "pypi"
      when "cargo"
        "cargo"
      when "hex"
        "hex"
      when "composer"
        "composer"
      when "nuget"
        "nuget"
      when "go_modules"
        "golang"
      when "docker"
        "docker"
      when "github_actions"
        "github"
      when "terraform"
        "terraform"
      when "pub"
        "pub"
      when "elm"
        "elm"
      else
        "generic"
      end
    end

    sig { params(dependency: Dependabot::Dependency).returns(String) }
    def scope_for(dependency)
      if dependency.production?
        "runtime"
      else
        "development"
      end
    end

    sig { params(dep: Dependabot::Dependency).returns(String) }
    def relationship_for(dep)
      if dep.direct?
        "direct"
      else
        "indirect"
      end
    end
  end
end
