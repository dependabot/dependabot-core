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
    attr_reader :ref
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
      @ref = T.let(T.must(job.source.branch), String)
      @sha = T.let(snapshot.base_commit_sha, String)
      @directory = T.let(T.must(job.source.directory), String)
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
        ref: ref,
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

    sig { params(snapshot: Dependabot::DependencySnapshot).returns(T::Hash[String, T.untyped]) }
    def build_manifests(snapshot)
      dependencies_by_manifest = {}

      # NOTE: This is reconstructing the manifest to dependency mapping
      #
      # It would require deep changes to the Dependabot::Snapshot and parsers,
      # but it might eventually be worth retaining this information from the
      # source files in order to avoid reconstructing it here?
      snapshot.dependencies.each do |dependency|
        dependency.requirements.each do |requirement|
          dependencies_by_manifest[requirement[:file]] ||= []
          dependencies_by_manifest[requirement[:file]] << dependency
        end
      end

      dependencies_by_manifest.each_with_object({}) do |(file, deps), manifests|
        # TODO: This approach won't work properly with multi-directory job definitions
        #
        # For now it is tolerable to omit this and limit our testing accordingly, but we
        # should behave sensibly in a multi-directory context as well
        file_path = File.join(directory, file).gsub(%r{^/}, "")

        manifests[file] = {
          name: file,
          file: {
            source_location: file_path
          },
          metadata: {
            ecosystem: T.must(snapshot.ecosystem).name
          },
          resolved: deps.uniq.each_with_object({}) do |dep, resolved|
            resolved[dep.name] = {
              package_url: build_purl(dep),
              # TODO: Replace relationship placeholder
              #
              # Dependabot has a bias towards operating on **declared dependencies**, so
              # we need to close gaps on transitive dependencies in a few places.
              #
              # This should be set in the parsers when we add capabilities to track immediate
              # dependencies.
              relationship: "direct",
              # TODO: Replace scope placeholder
              #
              # Dependabot::Dependency objects do include the `groups` a dependency is included in
              # that we could derive this from, but since group conventions vary by ecosystem
              # we should probably determine this in the parser and set the scope there.
              scope: "runtime",
              dependencies: [
                # TODO: Populate direct child dependencies
                #
                # Dependabot::Dependency objects do not include immediate dependencies,
                # this is a capability each parser will need to have added.
              ],
              metadata: {
                groups: dep.requirements.map { |r| r[:groups] }.flatten.join(", ")
              }
            }
          end
        }
      end
    end

    # Helper function to create a Package URL (purl)
    #
    # TODO: Move out of this class?
    #
    # It probably makes more sense to assign this to a Dependabot::Dependency
    # when it is created so the ecosystem-specific parser can own this?
    sig { params(dependency: Dependabot::Dependency).returns(String) }
    def build_purl(dependency)
      package_manager = dependency.package_manager
      name = dependency.name
      version = dependency.version

      case package_manager
      when "bundler"
        "pkg:gem/#{name}@#{version}"
      when "npm_and_yarn", "bun"
        "pkg:npm/#{name}@#{version}"
      when "maven", "gradle"
        "pkg:maven/#{name}@#{version}"
      when "pip", "uv"
        "pkg:pypi/#{name}@#{version}"
      when "cargo"
        "pkg:cargo/#{name}@#{version}"
      when "hex"
        "pkg:hex/#{name}@#{version}"
      when "composer"
        "pkg:composer/#{name}@#{version}"
      when "nuget"
        "pkg:nuget/#{name}@#{version}"
      when "go_modules"
        "pkg:golang/#{name}@#{version}"
      when "docker"
        "pkg:docker/#{name}@#{version}"
      when "github_actions"
        "pkg:github/#{name}@#{version}"
      when "terraform"
        "pkg:terraform/#{name}@#{version}"
      when "pub"
        "pkg:pub/#{name}@#{version}"
      when "elm"
        "pkg:elm/#{name}@#{version}"
      when "submodules"                 # TODO: Verify this is correct
        "pkg:github/#{name}@#{version}" # Use github format for submodules
      else
        "pkg:generic/#{name}@#{version}"
      end
    end
  end
end
