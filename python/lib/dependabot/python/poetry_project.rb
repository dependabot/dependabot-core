# typed: strict
# frozen_string_literal: true

require "fileutils"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/experiments"
require "dependabot/shared_helpers"
require "dependabot/python/name_normaliser"
require "dependabot/python/native_helpers"

module Dependabot
  module Python
    # Poetry's own view of a project, read through the native helper's
    # `parse_poetry_project` function. This class only exposes facts; callers
    # decide what to do with them.
    #
    # Gated behind the `enable_native_poetry_helper` experiment while the
    # helper is being evaluated.
    class PoetryProject
      extend T::Sig

      EXPERIMENT = :enable_native_poetry_helper

      MAIN_GROUP = "main"

      # Validates the helper's JSON so malformed output fails loudly.
      module Values
        extend T::Sig

        sig { params(value: T.nilable(Object), context: String).returns(T::Hash[String, Object]) }
        def self.object_hash(value, context)
          raise TypeError, "#{context} must be an object" unless value.is_a?(Hash)

          value.to_h { |key, item| [string(key, "#{context} key"), T.cast(item, Object)] }
        end

        sig { params(value: T.nilable(Object), context: String).returns(T::Array[Object]) }
        def self.array(value, context)
          raise TypeError, "#{context} must be an array" unless value.is_a?(Array)

          value.map { |item| T.cast(item, Object) }
        end

        sig { params(value: T.nilable(Object), context: String).returns(String) }
        def self.string(value, context)
          raise TypeError, "#{context} must be a string" unless value.is_a?(String)

          value
        end

        sig { params(value: T.nilable(Object), context: String).returns(T.nilable(String)) }
        def self.optional_string(value, context)
          value.nil? ? nil : string(value, context)
        end

        sig { params(value: T.nilable(Object), context: String).returns(T::Array[String]) }
        def self.string_array(value, context)
          array(value, context).map { |item| string(item, context) }
        end
      end

      # Locked from somewhere other than a package index. The existing parser
      # skips these lockfile entries, so callers do the same.
      DIRECT_SOURCE_TYPES = %w(directory file git url).freeze

      class LockedLink < T::ImmutableStruct
        const :name, String
        const :version, String
      end

      class LockedPackage < T::ImmutableStruct
        extend T::Sig

        const :name, String
        const :version, String
        const :groups, T::Array[String]
        # False when groups were worked out by walking a pre-2.1 lockfile.
        const :groups_from_lockfile, T::Boolean
        # Group name => PEP 508 marker. Nil before lock format 2.1.
        const :markers, T.nilable(T::Hash[String, T.nilable(String)])
        const :optional, T::Boolean
        const :source_type, T.nilable(String)
        const :dependencies, T::Array[LockedLink]

        sig { returns(T::Boolean) }
        def production?
          groups.include?(MAIN_GROUP) && !optional
        end

        sig { returns(T::Boolean) }
        def direct_source?
          DIRECT_SOURCE_TYPES.include?(source_type)
        end
      end

      class DeclaredSource < T::ImmutableStruct
        extend T::Sig

        # Nil for a named package index; "git", "directory", "file" or "url"
        # for a direct source.
        const :type, T.nilable(String)
        const :url, T.nilable(String)
        # Name of a `[[tool.poetry.source]]` entry.
        const :name, T.nilable(String)
        # Set only for git dependencies; Poetry's own `reference` merges these.
        const :tag, T.nilable(String)
        const :branch, T.nilable(String)
        const :rev, T.nilable(String)

        sig { returns(T::Boolean) }
        def direct?
          DIRECT_SOURCE_TYPES.include?(type)
        end
      end

      # One entry per declaration. A name declared with several constraints
      # (one per marker) appears several times, as does a name declared in
      # several groups.
      class DeclaredDependency < T::ImmutableStruct
        extend T::Sig

        const :name, String
        const :constraint, String
        const :groups, T::Array[String]
        const :markers, T.nilable(String)
        const :extras, T::Array[String]
        const :optional, T::Boolean
        const :source, T.nilable(DeclaredSource)

        sig { returns(T::Boolean) }
        def main?
          groups.include?(MAIN_GROUP)
        end
      end

      sig { returns(T::Boolean) }
      def self.enabled?
        Dependabot::Experiments.enabled?(EXPERIMENT)
      end

      # Loads the project when the experiment is on. Returns nil, so callers
      # keep their existing code path, when it's off, when there's no
      # pyproject.toml, or when Poetry can't load the project.
      sig do
        params(
          pyproject: T.nilable(Dependabot::DependencyFile),
          lockfile: T.nilable(Dependabot::DependencyFile)
        ).returns(T.nilable(PoetryProject))
      end
      def self.load_if_enabled(pyproject:, lockfile:)
        return unless enabled? && pyproject

        load(pyproject: pyproject, lockfile: lockfile)
      rescue SharedHelpers::HelperSubprocessFailed => e
        Dependabot.logger.warn("Native Poetry helper failed, using the existing Poetry code path: #{e.message}")
        nil
      end

      sig do
        params(
          pyproject: Dependabot::DependencyFile,
          lockfile: T.nilable(Dependabot::DependencyFile)
        ).returns(PoetryProject)
      end
      def self.load(pyproject:, lockfile:)
        result = SharedHelpers.in_a_temporary_directory do
          [pyproject, lockfile].compact.each do |file|
            FileUtils.mkdir_p(File.dirname(file.name))
            File.write(file.name, file.content)
          end

          SharedHelpers.run_helper_subprocess(
            command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
            function: "parse_poetry_project",
            args: [File.dirname(pyproject.name)]
          )
        end

        new(result)
      end

      sig { params(result: Object).void }
      def initialize(result)
        hash = Values.object_hash(result, "parse_poetry_project result")
        @groups_and_markers_locked = T.let(hash["groups_and_markers_locked"] == true, T::Boolean)
        @locked_packages = T.let(
          Values.array(hash.fetch("locked", []), "locked packages").map { |entry| locked_package_from(entry) },
          T::Array[LockedPackage]
        )
        @declared_dependencies = T.let(
          Values.array(hash.fetch("declared", []), "declared dependencies").map { |entry| declared_from(entry) },
          T::Array[DeclaredDependency]
        )
      end

      sig { returns(T::Array[LockedPackage]) }
      attr_reader :locked_packages

      sig { returns(T::Array[DeclaredDependency]) }
      attr_reader :declared_dependencies

      sig { returns(T::Boolean) }
      def groups_and_markers_locked?
        @groups_and_markers_locked
      end

      sig { params(name: String).returns(T::Array[LockedPackage]) }
      def locked_versions_of(name)
        locked_by_name.fetch(NameNormaliser.normalise(name), [])
      end

      sig { returns(T::Array[String]) }
      def production_dependency_names
        locked_packages.select(&:production?).map(&:name).uniq
      end

      private

      sig { returns(T::Hash[String, T::Array[LockedPackage]]) }
      def locked_by_name
        @locked_by_name ||= T.let(
          locked_packages.group_by(&:name),
          T.nilable(T::Hash[String, T::Array[LockedPackage]])
        )
      end

      sig { params(entry: Object).returns(LockedPackage) }
      def locked_package_from(entry)
        hash = Values.object_hash(entry, "locked package")
        LockedPackage.new(
          name: NameNormaliser.normalise(Values.string(hash["name"], "locked package name")),
          version: Values.string(hash["version"], "locked package version"),
          groups: Values.string_array(hash.fetch("groups", []), "locked package groups"),
          groups_from_lockfile: hash["groups_from_lockfile"] == true,
          markers: markers_from(hash["markers"]),
          optional: hash["optional"] == true,
          source_type: source_type_from(hash["source"]),
          dependencies: Values.array(hash.fetch("dependencies", []), "locked dependencies").flat_map do |dep|
            links_from(dep)
          end
        )
      end

      sig { params(entry: Object).returns(DeclaredDependency) }
      def declared_from(entry)
        hash = Values.object_hash(entry, "declared dependency")
        DeclaredDependency.new(
          name: NameNormaliser.normalise(Values.string(hash["name"], "declared dependency name")),
          constraint: Values.string(hash["constraint"], "declared dependency constraint"),
          groups: Values.string_array(hash.fetch("groups", []), "declared dependency groups"),
          markers: Values.optional_string(hash["markers"], "declared dependency markers"),
          extras: Values.string_array(hash.fetch("extras", []), "declared dependency extras"),
          optional: hash["optional"] == true,
          source: declared_source_from(hash["source"], hash["git_ref"])
        )
      end

      sig { params(source: T.nilable(Object), git_ref: T.nilable(Object)).returns(T.nilable(DeclaredSource)) }
      def declared_source_from(source, git_ref)
        return if source.nil?

        fields = Values.object_hash(source, "declared source")
        ref = git_ref.nil? ? {} : Values.object_hash(git_ref, "declared git reference")
        DeclaredSource.new(
          type: Values.optional_string(fields["type"], "declared source type"),
          url: Values.optional_string(fields["url"], "declared source url"),
          name: Values.optional_string(fields["name"], "declared source name"),
          tag: Values.optional_string(ref["tag"], "declared git tag"),
          branch: Values.optional_string(ref["branch"], "declared git branch"),
          rev: Values.optional_string(ref["rev"], "declared git rev")
        )
      end

      sig { params(source: T.nilable(Object)).returns(T.nilable(String)) }
      def source_type_from(source)
        return if source.nil?

        Values.optional_string(Values.object_hash(source, "source")["type"], "source type")
      end

      sig { params(dependency: Object).returns(T::Array[LockedLink]) }
      def links_from(dependency)
        resolved = Values.object_hash(dependency, "locked dependency").fetch("resolved", [])
        Values.array(resolved, "resolved links").map do |link|
          link_hash = Values.object_hash(link, "resolved link")
          LockedLink.new(
            name: NameNormaliser.normalise(Values.string(link_hash["name"], "resolved link name")),
            version: Values.string(link_hash["version"], "resolved link version")
          )
        end
      end

      sig { params(value: T.nilable(Object)).returns(T.nilable(T::Hash[String, T.nilable(String)])) }
      def markers_from(value)
        return if value.nil?

        Values.object_hash(value, "locked package markers").transform_values do |marker|
          Values.optional_string(marker, "locked package marker")
        end
      end
    end
  end
end
