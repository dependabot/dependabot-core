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
        _dependencies: T::Array[Dependabot::Dependency]
      ).returns(T::Hash[String, T.untyped])
    end
    def build_manifests(dependency_files, _dependencies)
      dependencies_by_manifest = {}
      relevant_manifests(dependency_files).each do |file|
        dependencies_by_manifest[file.path] ||= []
        file.dependencies.each do |dependency|
          dependencies_by_manifest[file.path] << dependency
        end
      end

      dependencies_by_manifest.each_with_object({}) do |(file, deps), manifests|
        # source location is relative to the root of the repo, so we strip the leading slash
        source_location = file.gsub(%r{^/}, "")

        manifests[file] = {
          name: file,
          file: {
            source_location: source_location
          },
          metadata: {
            ecosystem: package_manager
          },
          resolved: deps.uniq.each_with_object({}) do |dep, resolved|
            resolved[dep.name] = {
              package_url: build_purl(dep),
              relationship: relationship_for(dep),
              scope: scope_for(dep),
              dependencies: [
                # TODO: Populate direct child dependencies
                #
                # Dependabot::Dependency objects do not include immediate dependencies,
                # this is a capability each parser will need to have added.
              ],
              metadata: {}
            }
          end
        }
      end
    end

    # For each distinct directory in our manifest list, we only want the highest priority manifests available,
    # this method will filter out manifests for directories that have lockfiles and so on.
    sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile]) }
    def relevant_manifests(dependency_files)
      manifests_by_directory = dependency_files.each_with_object({}) do |file, dirs|
        # If the file doesn't have any dependencies assigned to it, then it isn't relevant.
        next if file.dependencies.empty?

        # Build up a dictionary of unique directories...
        dirs[file.directory] ||= {}
        # Add a list of files for each distinct priority...
        dirs[file.directory][file.priority] ||= []
        dirs[file.directory][file.priority] << file
      end

      manifests_by_directory.map do |_directory, manifests_by_priority|
        # ... and cherry pick the highest priority list for each directory
        manifests_by_priority[manifests_by_priority.keys.max]
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
      if dep.direct?
        "direct"
      else
        "indirect"
      end
    end
  end
end
