# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/package/release_cooldown_options"
require "dependabot/requirements_update_strategy"
require "dependabot/shared_helpers"
require "dependabot/uv/file_parser"
require "dependabot/uv/file_updater/lock_file_error_handler"
require "dependabot/uv/file_updater/lock_file_updater"
require "dependabot/uv/lockfile_document"
require "dependabot/uv/name_normaliser"
require "dependabot/uv/version"
require "dependabot/uv/update_checker"
require "dependabot/uv/update_checker/latest_version_finder"
require "dependabot/uv/update_checker/requirements_updater"

module Dependabot
  module Uv
    class UpdateChecker
      # Moves a dependency together with the direct dependencies it is pinned in lockstep with
      # (e.g. opentelemetry-api and opentelemetry-sdk), which uv can only resolve when both pins move.
      class LockstepResolver
        extend T::Sig

        MAX_UNLOCK_ROUNDS = 3

        class Probe < T::ImmutableStruct
          const :resolved, T::Boolean
          const :locked_versions, T::Hash[String, T::Array[String]], default: {}
          const :conflict_names, T::Array[String], default: []
        end

        sig { returns(T.nilable(Gem::Version)) }
        attr_reader :rejected_version

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String),
            requirements_update_strategy: Dependabot::RequirementsUpdateStrategy,
            update_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          repo_contents_path:,
          requirements_update_strategy:,
          update_cooldown:
        )
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @repo_contents_path = repo_contents_path
          @requirements_update_strategy = requirements_update_strategy
          @update_cooldown = update_cooldown
          @rejected_version = T.let(nil, T.nilable(Gem::Version))
          @own_probes = T.let({}, T::Hash[String, Probe])
          @full_unlock_updates = T.let({}, T::Hash[String, T.nilable(T::Array[Dependabot::Dependency])])
          @neighbours_in_lockfile = T.let(nil, T.nilable(T::Boolean))
          @top_level_dependencies = T.let(nil, T.nilable(T::Array[Dependabot::Dependency]))
          @original_locked_versions = T.let(nil, T.nilable(T::Hash[String, T::Array[String]]))
        end

        sig { returns(T::Boolean) }
        def neighbours_in_lockfile?
          @neighbours_in_lockfile = compute_neighbours_in_lockfile if @neighbours_in_lockfile.nil?
          @neighbours_in_lockfile
        end

        # Only a resolution conflict that names another direct dependency counts. Other resolution failures
        # (e.g. a release that needs a newer Python) return false so the file updater still reports them;
        # errors that aren't resolution failures are raised here.
        sig { params(version: Gem::Version).returns(T::Boolean) }
        def lockstep_conflict?(version)
          result = own_probe(version)
          conflict = !result.resolved && eligible_peers(result.conflict_names).any?
          @rejected_version = version if conflict
          conflict
        end

        sig { params(version: Gem::Version).returns(T.nilable(T::Array[Dependabot::Dependency])) }
        def updated_dependencies_after_full_unlock(version)
          key = version.to_s
          return @full_unlock_updates[key] if @full_unlock_updates.key?(key)

          @full_unlock_updates[key] = resolve_with_peers(version)
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { returns(Dependabot::RequirementsUpdateStrategy) }
        attr_reader :requirements_update_strategy

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :update_cooldown

        sig { params(version: Gem::Version).returns(T.nilable(T::Array[Dependabot::Dependency])) }
        def resolve_with_peers(version)
          peers = T.let([], T::Array[Dependabot::Dependency])

          MAX_UNLOCK_ROUNDS.times do
            # Round 1 has no peers: reuse the cached own probe so :own then :all runs uv once for it
            result = peers.empty? ? own_probe(version) : probe(version, peers)
            return updates_from(version, peers, result) if result.resolved

            new_peers = eligible_peers(result.conflict_names).reject do |peer|
              peers.any? { |existing| normalise(existing.name) == normalise(peer.name) }
            end
            return nil if new_peers.empty?

            peers += new_peers
          end

          nil
        end

        sig do
          params(
            version: Gem::Version,
            peers: T::Array[Dependabot::Dependency],
            result: Probe
          ).returns(T.nilable(T::Array[Dependabot::Dependency]))
        end
        def updates_from(version, peers, result)
          return nil unless result.locked_versions[normalise(dependency.name)] == [version.to_s]

          moved = T.let([], T::Array[Dependabot::Dependency])
          peers.each do |peer|
            versions = result.locked_versions.fetch(normalise(peer.name), [])
            # A single pin can't express a forked resolution
            return nil unless versions.length == 1

            new_version = T.must(versions.first)
            next if new_version == peer.version
            return nil if in_cooldown?(peer, new_version)

            moved << updated_dependency(peer, new_version)
          end
          return nil if moved.empty?

          [updated_dependency(dependency, version.to_s), *moved.sort_by(&:name)]
        end

        sig { params(version: Gem::Version).returns(Probe) }
        def own_probe(version)
          @own_probes[version.to_s] ||= probe(version, [])
        end

        sig { params(version: Gem::Version, peers: T::Array[Dependabot::Dependency]).returns(Probe) }
        def probe(version, peers)
          updated_files = FileUpdater::LockFileUpdater.new(
            dependencies: [
              updated_dependency(dependency, version.to_s),
              *peers.map { |peer| relaxed_dependency(peer) }
            ],
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path,
            upgrade_package_names: [dependency.name]
          ).updated_dependency_files

          lockfile = updated_files.find { |file| file.name == "uv.lock" } || T.must(original_lockfile)
          Probe.new(resolved: true, locked_versions: locked_versions(lockfile))
        rescue Dependabot::DependencyFileContentNotChanged
          Probe.new(resolved: true, locked_versions: original_locked_versions)
        rescue Dependabot::UpdateNotPossible => e
          Probe.new(resolved: false, conflict_names: update_not_possible_names(e))
        rescue Dependabot::DependencyFileNotResolvable => e
          raise unless resolution_conflict?(e.message)

          Probe.new(resolved: false, conflict_names: error_handler.conflict_package_names(e.message))
        end

        # UpdateNotPossible only names the first two packages of uv's derivation, so a peer further down
        # (e.g. an sdk depending on the api through a third package) is read from the original uv output.
        sig { params(error: Dependabot::UpdateNotPossible).returns(T::Array[String]) }
        def update_not_possible_names(error)
          names = error.dependencies.map { |name| normalise(name) }
          cause = error.cause
          return names unless cause.is_a?(SharedHelpers::HelperSubprocessFailed)

          (error_handler.conflict_package_names(cause.message) + names).uniq
        end

        sig { params(message: String).returns(T::Boolean) }
        def resolution_conflict?(message)
          message.match?(FileUpdater::LockFileErrorHandler::UV_UNRESOLVABLE_REGEX) ||
            message.include?(FileUpdater::LockFileErrorHandler::RESOLUTION_IMPOSSIBLE_ERROR)
        end

        sig { params(names: T::Array[String]).returns(T::Array[Dependabot::Dependency]) }
        def eligible_peers(names)
          wanted = names.map { |name| normalise(name) } - [normalise(dependency.name)]

          eligible = top_level_dependencies.select do |dep|
            name = normalise(dep.name)
            wanted.include?(name) &&
              !dep.version.nil? &&
              !build_system_only?(dep) &&
              !local_package_names.include?(name) &&
              original_locked_versions.fetch(name, []).length == 1
          end
          eligible.uniq { |dep| normalise(dep.name) }
        end

        sig { params(dep: Dependabot::Dependency, version: String).returns(Dependabot::Dependency) }
        def updated_dependency(dep, version)
          Dependabot::Dependency.new(
            name: dep.name,
            version: version,
            previous_version: dep.version,
            requirements: RequirementsUpdater.new(
              requirements: dep.requirements,
              latest_resolvable_version: version,
              update_strategy: requirements_update_strategy,
              has_lockfile: dep.requirements.any? { |req| req.file&.end_with?("requirements.txt") }
            ).updated_requirements,
            previous_requirements: dep.requirements,
            package_manager: dep.package_manager,
            metadata: dep.metadata,
            subdependency_metadata: dep.subdependency_metadata
          )
        end

        # `>=` the locked version without --upgrade-package: uv keeps the peer unless the bump forces it
        # to move, then picks the highest version that fits.
        sig { params(peer: Dependabot::Dependency).returns(Dependabot::Dependency) }
        def relaxed_dependency(peer)
          Dependabot::Dependency.new(
            name: peer.name,
            version: nil,
            previous_version: peer.version,
            requirements: peer.requirements.map do |req|
              next req unless req.file&.end_with?("pyproject.toml")

              req.merge(requirement: ">=#{peer.version}")
            end,
            previous_requirements: peer.requirements,
            package_manager: peer.package_manager
          )
        end

        sig { params(peer: Dependabot::Dependency, new_version: String).returns(T::Boolean) }
        def in_cooldown?(peer, new_version)
          return false if update_cooldown.nil?

          latest_allowed = LatestVersionFinder.new(
            dependency: peer,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: [],
            raise_on_ignored: false,
            cooldown_options: update_cooldown,
            security_advisories: []
          ).latest_version
          latest_allowed.nil? || Uv::Version.new(new_version) > latest_allowed
        end

        sig { returns(T::Boolean) }
        def compute_neighbours_in_lockfile
          return false unless original_lockfile

          name = normalise(dependency.name)
          others = top_level_dependencies.map { |dep| normalise(dep.name) }.uniq - [name]
          return false if others.empty?

          lockfile_document.graph_packages.any? do |package|
            package_name = package.name
            next false if package_name.nil?

            linked = linked_names(package)
            if normalise(package_name) == name
              linked.intersect?(others)
            else
              others.include?(normalise(package_name)) && linked.include?(name)
            end
          end
        end

        sig { params(package: LockfileDocument::GraphPackage).returns(T::Array[String]) }
        def linked_names(package)
          (package.dependencies + package.optional_dependencies + package.dev_dependencies)
            .map { |linked| normalise(linked) }
        end

        sig { params(dep: Dependabot::Dependency).returns(T::Boolean) }
        def build_system_only?(dep)
          groups = dep.requirements.flat_map { |req| req.groups || [] }.compact.uniq
          !groups.empty? && groups.all?("build-system")
        end

        sig { returns(T::Array[String]) }
        def local_package_names
          lockfile_document.graph_packages.select(&:local_source).filter_map(&:name).map { |name| normalise(name) }
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def top_level_dependencies
          @top_level_dependencies ||=
            FileParser.new(dependency_files: dependency_files, source: nil, credentials: credentials)
                      .parse
                      .select { |dep| dep.requirements.any? { |req| req.file&.end_with?("pyproject.toml") } }
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def original_locked_versions
          @original_locked_versions ||= locked_versions(T.must(original_lockfile))
        end

        sig { params(lockfile: Dependabot::DependencyFile).returns(T::Hash[String, T::Array[String]]) }
        def locked_versions(lockfile)
          versions = T.let(Hash.new { |hash, key| hash[key] = [] }, T::Hash[String, T::Array[String]])
          LockfileDocument.from_file(lockfile).resolution_packages.each do |package|
            T.must(versions[normalise(package.name)]) << package.version
          end
          versions.transform_values(&:uniq)
        end

        sig { returns(LockfileDocument) }
        def lockfile_document
          LockfileDocument.from_file(T.must(original_lockfile))
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def original_lockfile
          dependency_files.find { |file| file.name == "uv.lock" }
        end

        sig { returns(FileUpdater::LockFileErrorHandler) }
        def error_handler
          FileUpdater::LockFileErrorHandler.new
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
        end
      end
    end
  end
end
