# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/uv/file_parser"
require "dependabot/uv/lockfile_document"

module Dependabot
  module Uv
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      RUNTIME_GROUP = "dependencies"
      DEV_GROUP = "dev-dependencies"

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        uv_lock || raise(DependabotError, "No uv.lock present; uv graphing requires a lockfile.")
      end

      # uv.lock is guaranteed to be present when graphing runs - the
      # dependabot-api EcosystemFileDetector only routes UV jobs when it sees
      # a uv.lock in the repo. We parse uv.lock directly rather than
      # delegating to FileParser, so the graph reflects only what uv resolved.
      sig { override.void }
      def prepare!
        raise DependabotError, "No uv.lock present; uv graphing requires a lockfile." unless uv_lock

        prepare_from_lockfile!
      end

      private

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        dependency_names = @dependencies.map(&:name)
        package_relationships.fetch(dependency.name, []).select { |child| dependency_names.include?(child) }
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def package_relationships
        @package_relationships ||= T.let(
          package_relationships_from_lockfile(T.must(uv_lock)),
          T.nilable(T::Hash[String, T::Array[String]])
        )
      end

      sig { void }
      def prepare_from_lockfile!
        document = LockfileDocument.from_file(T.must(uv_lock))
        packages = document.graph_packages

        root_names = root_package_names(packages, document.workspace_members.to_set)
        direct_runtime, direct_dev = direct_dependency_names(packages, root_names)

        @dependencies = packages.filter_map do |pkg|
          build_dependency(pkg, root_names, direct_runtime, direct_dev)
        end
        @prepared = true
      rescue StandardError => e
        # If uv.lock is unparseable we can't build a graph at all, but we still
        # want the rest of the submission flow to continue (matching the prior
        # behaviour where lockfile parse failures only marked subdependency
        # fetching as errored).
        errored_fetching_subdependencies!
        @subdependency_error = e
        Dependabot.logger.error("Failed to parse uv.lock for graphing: #{e.message}")
        @dependencies = []
        @prepared = true
      end

      sig { params(lockfile: Dependabot::DependencyFile).returns(T::Hash[String, T::Array[String]]) }
      def package_relationships_from_lockfile(lockfile)
        relationships = T.let({}, T::Hash[String, T::Array[String]])
        LockfileDocument.from_file(lockfile).graph_packages.each_with_object(relationships) do |package, rels|
          name = package.name
          next unless name

          parent = normalised_dependency_name(name)
          (rels[parent] ||= []).concat(lockfile_child_names(package))
        end
      rescue StandardError => e
        errored_fetching_subdependencies!
        @subdependency_error = e
        Dependabot.logger.error("Failed to parse uv.lock relationships: #{e.message}")
        {}
      end

      # Mirrors uv's `create_dependencies` (crates/uv-resolver/src/lock/export/cyclonedx_json.rs),
      # which chains a package's `dependencies`, `optional-dependencies`, and
      # `dev-dependencies` when building the SBOM dependency graph.
      sig { params(package: LockfileDocument::GraphPackage).returns(T::Array[String]) }
      def lockfile_child_names(package)
        names = package.dependencies + package.optional_dependencies + package.dev_dependencies
        names.map { |name| normalised_dependency_name(name) }.uniq
      end

      # Identifies the workspace member packages whose `dependencies`,
      # `optional-dependencies`, and `dev-dependencies` arrays describe the
      # project's direct deps.
      #
      # Authoritative signal: the `[manifest] members = [...]` array, which uv
      # writes for multi-member workspaces. See
      # https://github.com/astral-sh/uv/blob/main/crates/uv-resolver/src/lock/mod.rs
      # ("manifest_table.insert(\"members\", ...)" and the workspace-member
      # lookup `self.members().contains(&package.id.name)`).
      #
      # Fallback for single-member workspaces (which omit `[manifest] members`):
      # match packages whose `source` is a local variant — `virtual`, `editable`,
      # or `directory` — per the `SourceWire` enum in the same file.
      sig do
        params(packages: T::Array[LockfileDocument::GraphPackage], declared: T::Set[String]).returns(T::Set[String])
      end
      def root_package_names(packages, declared)
        return declared unless declared.empty?

        packages.each_with_object(Set.new) do |pkg, set|
          next unless pkg.local_source

          name = pkg.name
          set << name if name
        end
      end

      # Mirrors uv's `ExportableRequirements::from_lock` (crates/uv-resolver/src/lock/export/mod.rs)
      # when invoked with `--all-extras --all-groups`: each workspace root contributes its
      # `dependencies` as direct runtime, `optional-dependencies` (all extras) as direct runtime,
      # and `dev-dependencies` (all groups) as direct dev. We use --all-extras/--all-groups
      # semantics because the dependency graph reports what *could* be installed, not what was
      # selected for a particular sync.
      sig do
        params(packages: T::Array[LockfileDocument::GraphPackage], root_names: T::Set[String])
          .returns([T::Set[String], T::Set[String]])
      end
      def direct_dependency_names(packages, root_names)
        runtime = T.let(Set.new, T::Set[String])
        dev = T.let(Set.new, T::Set[String])

        packages.each do |pkg|
          name = pkg.name
          next unless name && root_names.include?(name)

          runtime.merge(pkg.dependencies)
          runtime.merge(pkg.optional_dependencies)
          dev.merge(pkg.dev_dependencies)
        end

        [runtime, dev]
      end

      sig do
        params(
          pkg: LockfileDocument::GraphPackage,
          root_names: T::Set[String],
          direct_runtime: T::Set[String],
          direct_dev: T::Set[String]
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def build_dependency(pkg, root_names, direct_runtime, direct_dev)
        name = pkg.name
        version = pkg.version
        return unless name && version

        # Root project packages get requirements: [] (indirect, runtime) to
        # match the prior FileParser-derived behaviour where uv.lock packages
        # without a pyproject entry surfaced as indirect.
        groups = root_names.include?(name) ? [] : direct_groups_for(name, direct_runtime, direct_dev)
        requirements = groups.empty? ? [] : [{ requirement: nil, file: "uv.lock", source: nil, groups: groups }]

        Dependabot::Dependency.new(
          name: normalised_dependency_name(name),
          version: version,
          requirements: requirements,
          package_manager: "uv"
        )
      end

      # A dependency listed under both runtime and dev groups stays runtime;
      # uv's production check returns true if "dependencies" is present.
      sig do
        params(name: String, direct_runtime: T::Set[String], direct_dev: T::Set[String])
          .returns(T::Array[String])
      end
      def direct_groups_for(name, direct_runtime, direct_dev)
        return [RUNTIME_GROUP] if direct_runtime.include?(name)
        return [DEV_GROUP] if direct_dev.include?(name)

        []
      end

      sig { params(name: String).returns(String) }
      def normalised_dependency_name(name)
        Dependabot::Uv::FileParser.normalize_dependency_name(name)
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "pypi"
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def uv_lock
        return @uv_lock if defined?(@uv_lock)

        @uv_lock = T.let(
          dependency_files.find { |f| f.name == "uv.lock" } ||
            dependency_files.find { |f| f.name.end_with?("/uv.lock") },
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::DependencyGraphers.register("uv", Dependabot::Uv::DependencyGrapher)
