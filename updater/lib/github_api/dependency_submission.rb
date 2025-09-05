# typed: strong
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

      file = relevant_dependency_file(dependency_files)

      {
        file.path => {
          name: file.path,
          file: {
            source_location: file.path.gsub(%r{^/}, "")
          },
          metadata: {
            ecosystem: package_manager
          },
          resolved: dependencies.uniq.each_with_object({}) do |dep, resolved|
            resolved[dep.name] = {
              package_url: build_purl(dep),
              relationship: relationship_for(dep),
              scope: scope_for(dep),
              # We expect direct dependencies to be added to the metadata, but they may not always be available
              dependencies: dep.metadata.fetch(:depends_on, []),
              metadata: {}
            }
          end
        }
      }
    end

    # Dependabot aligns with Dependency Graph's existing behaviour where all dependencies are attributed to the
    # most specific file out of the manifest or lockfile for the directory rather than split direct and indirect
    # to the manifest and lockfile respectively.
    #
    # Dependabot's parsers apply this precedence by deterministic ordering, i.e. the manifest file's dependencies
    # are added to the set first, then the lockfiles so we want the right-most file in the set, excluding anything
    # marked as a support file.
    sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(Dependabot::DependencyFile) }
    def relevant_dependency_file(dependency_files)
      filtered_files = dependency_files.reject { |f| f.support_file? || f.vendored_file? }

      # TODO(brrygrdn): Make relevant_dependency_file an ecosystem property
      #
      # It turns out that the right-most-file-aligns-with-dependency-graph-static-parsing strategy isn't a durable
      # assumption, for Go we prefer go.mod over go.sum even though the latter is technically the lockfile.
      #
      # With python ecosystems, this gets more fragmented and it isn't always accurate for 'bun' Javascript projects
      # if they use mixins.
      #
      # The correct way to solve this is to use Dependency Injection to provide a small ecosystem-specific helper
      # for this and PURLs so we can define the correct heuristic as necessary and use the 'last file wins' as our
      # fallback strategy.
      if %w(bun go Python).include?(package_manager)
        T.must(filtered_files.first)
      else
        T.must(filtered_files.last)
      end
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
      "pkg:#{purl_pkg_for(dependency.package_manager)}/#{dependency.name}@#{dependency.version}".chomp("@")
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
      if dep.top_level?
        "direct"
      else
        "indirect"
      end
    end
  end
end
