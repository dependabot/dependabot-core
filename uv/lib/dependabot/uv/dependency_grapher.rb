# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/uv/file_parser"
require "toml-rb"

module Dependabot
  module Uv
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      RUNTIME_GROUP = T.let("dependencies", String)
      DEV_GROUP = T.let("dev-dependencies", String)

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        uv_lock || raise(DependabotError, "No uv.lock present; uv graphing requires a lockfile.")
      end

      # uv.lock is guaranteed to be present when graphing runs - the
      # dependabot-api EcosystemFileDetector only routes UV jobs when it sees
      # a uv.lock in the repo. We override prepare! to parse uv.lock directly
      # rather than delegating to FileParser, so the graph reflects only what
      # uv actually resolved (no requirements.txt / pyproject.toml inputs).
      sig { override.void }
      def prepare!
        raise DependabotError, "No uv.lock present; uv graphing requires a lockfile." unless uv_lock

        parsed = TomlRB.parse(T.must(T.must(uv_lock).content))
        packages = T.cast(parsed.fetch("package", []), T::Array[T.untyped])
        manifest = parsed.fetch("manifest", {})

        root_names = root_package_names(packages, manifest)
        direct_runtime, direct_dev = direct_dependency_names(packages, root_names)

        @dependencies = packages.filter_map do |pkg|
          build_dependency(pkg, root_names, direct_runtime, direct_dev)
        end
        @prepared = true
      rescue DependabotError
        raise
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

      private

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        dependency_names = @dependencies.map(&:name)
        package_relationships.fetch(dependency.name, []).select { |child| dependency_names.include?(child) }
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def package_relationships
        @package_relationships ||= T.let(
          package_relationships_from_lockfile(T.must(T.must(uv_lock).content)),
          T.nilable(T::Hash[String, T::Array[String]])
        )
      end

      sig { params(lockfile_content: String).returns(T::Hash[String, T::Array[String]]) }
      def package_relationships_from_lockfile(lockfile_content)
        lockfile_packages(lockfile_content).each_with_object({}) do |package_data, rels|
          parent = lockfile_parent_name(package_data)
          next unless parent

          rels[parent] ||= []
          rels[parent].concat(lockfile_child_names(package_data))
        end
      rescue StandardError => e
        errored_fetching_subdependencies!
        @subdependency_error = e
        Dependabot.logger.error("Failed to parse uv.lock relationships: #{e.message}")
        {}
      end

      sig { params(lockfile_content: String).returns(T::Array[T.untyped]) }
      def lockfile_packages(lockfile_content)
        parsed = TomlRB.parse(lockfile_content)
        T.cast(parsed.fetch("package", []), T::Array[T.untyped])
      end

      sig { params(package_data: T.untyped).returns(T.nilable(String)) }
      def lockfile_parent_name(package_data)
        return unless package_data.is_a?(Hash)

        package_name = package_data["name"]
        return unless package_name.is_a?(String)

        normalised_dependency_name(package_name)
      end

      # Mirrors uv's `create_dependencies` (crates/uv-resolver/src/lock/export/cyclonedx_json.rs),
      # which chains a package's `dependencies`, `optional-dependencies`, and
      # `dev-dependencies` when building the SBOM dependency graph.
      sig { params(package_data: T.untyped).returns(T::Array[String]) }
      def lockfile_child_names(package_data)
        return [] unless package_data.is_a?(Hash)

        names = T.let([], T::Array[String])
        collect_dep_names(package_data["dependencies"], names)
        collect_dep_names_from_groups(package_data["optional-dependencies"], names)
        collect_dep_names_from_groups(package_data["dev-dependencies"], names)
        names.map { |name| normalised_dependency_name(name) }.uniq
      end

      sig { params(dependency_data: T.untyped).returns(T.nilable(String)) }
      def lockfile_dependency_name(dependency_data)
        if dependency_data.is_a?(Hash)
          name = dependency_data["name"]
          return name if name.is_a?(String)
        end

        return dependency_data if dependency_data.is_a?(String)

        nil
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
      sig { params(packages: T::Array[T.untyped], manifest: T.untyped).returns(T::Set[String]) }
      def root_package_names(packages, manifest)
        declared = declared_workspace_members(manifest)
        return declared unless declared.empty?

        packages.each_with_object(Set.new) do |pkg, set|
          next unless pkg.is_a?(Hash)

          source = pkg["source"]
          next unless source.is_a?(Hash)
          next unless source.key?("virtual") || source.key?("editable") || source.key?("directory")

          name = pkg["name"]
          set << name if name.is_a?(String)
        end
      end

      sig { params(manifest: T.untyped).returns(T::Set[String]) }
      def declared_workspace_members(manifest)
        return Set.new unless manifest.is_a?(Hash)

        members = manifest["members"]
        return Set.new unless members.is_a?(Array)

        members.each_with_object(Set.new) do |name, set|
          set << name if name.is_a?(String)
        end
      end

      # Mirrors uv's `ExportableRequirements::from_lock` (crates/uv-resolver/src/lock/export/mod.rs)
      # when invoked with `--all-extras --all-groups`: each workspace root contributes its
      # `dependencies` as direct runtime, `optional-dependencies` (all extras) as direct runtime,
      # and `dev-dependencies` (all groups) as direct dev. We use --all-extras/--all-groups
      # semantics because the dependency graph reports what *could* be installed, not what was
      # selected for a particular sync.
      sig do
        params(packages: T::Array[T.untyped], root_names: T::Set[String])
          .returns([T::Set[String], T::Set[String]])
      end
      def direct_dependency_names(packages, root_names)
        runtime = T.let(Set.new, T::Set[String])
        dev = T.let(Set.new, T::Set[String])

        packages.each do |pkg|
          next unless pkg.is_a?(Hash) && root_names.include?(pkg["name"])

          collect_dep_names(pkg["dependencies"], runtime)
          collect_dep_names_from_groups(pkg["optional-dependencies"], runtime)
          collect_dep_names_from_groups(pkg["dev-dependencies"], dev)
        end

        [runtime, dev]
      end

      sig { params(entries: T.untyped, collection: T.any(T::Set[String], T::Array[String])).void }
      def collect_dep_names(entries, collection)
        return unless entries.is_a?(Array)

        entries.each do |entry|
          name = lockfile_dependency_name(entry)
          collection << name if name.is_a?(String)
        end
      end

      sig { params(groups: T.untyped, collection: T.any(T::Set[String], T::Array[String])).void }
      def collect_dep_names_from_groups(groups, collection)
        return unless groups.is_a?(Hash)

        groups.each_value { |entries| collect_dep_names(entries, collection) }
      end

      sig do
        params(
          pkg: T.untyped,
          root_names: T::Set[String],
          direct_runtime: T::Set[String],
          direct_dev: T::Set[String]
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def build_dependency(pkg, root_names, direct_runtime, direct_dev)
        return unless pkg.is_a?(Hash)

        name = pkg["name"]
        version = pkg["version"]
        return unless name.is_a?(String) && version.is_a?(String)

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
          dependency_files.find { |f| f.name == "uv.lock" },
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::DependencyGraphers.register("uv", Dependabot::Uv::DependencyGrapher)
