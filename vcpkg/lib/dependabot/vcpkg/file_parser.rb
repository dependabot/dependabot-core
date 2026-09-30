# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/logger"

require "dependabot/vcpkg"
require "dependabot/vcpkg/language"
require "dependabot/vcpkg/manifest_baseline"
require "dependabot/vcpkg/manifest_document"
require "dependabot/vcpkg/package/versions_database"
require "dependabot/vcpkg/package_manager"
require "dependabot/vcpkg/version"

module Dependabot
  module Vcpkg
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependencies = dependency_files.flat_map { |file| parse_dependency_file(file) }.compact
        baseline = missing_baseline_dependency
        dependencies << baseline if baseline
        dependencies
      end

      sig { override.returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any? do |f|
          [VCPKG_JSON_FILENAME, VCPKG_CONFIGURATION_JSON_FILENAME].include?(f.name)
        end

        raise Dependabot::DependencyFileNotFound.new(nil, "No vcpkg manifest files found")
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_dependency_file(dependency_file)
        return [] unless dependency_file.content

        case dependency_file.name
        when VCPKG_JSON_FILENAME then parse_vcpkg_json(dependency_file)
        when VCPKG_CONFIGURATION_JSON_FILENAME then parse_vcpkg_configuration_json(dependency_file)
        else []
        end
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_vcpkg_json(dependency_file)
        document = ManifestDocument.from_file(dependency_file)

        dependencies = []

        baseline = document.builtin_baseline
        if baseline
          dependencies << Dependabot::Dependency.new(
            name: VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME,
            version: baseline,
            package_manager: "vcpkg",
            requirements: [{
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: VCPKG_DEFAULT_BASELINE_URL,
                ref: VCPKG_DEFAULT_BASELINE_DEFAULT_BRANCH
              },
              file: dependency_file.name
            }]
          )
        end

        document.ports.each do |port|
          dependency = build_port_dependency(name: port.name, constraint: port.constraint, dependency_file:)
          dependencies << dependency if dependency
        end

        dependencies.compact
      rescue Dependabot::DependencyFileNotParseable => e
        Dependabot.logger.warn(e.message)
        raise
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_vcpkg_configuration_json(dependency_file)
        document = ManifestDocument.from_file(dependency_file)

        dependencies = []

        # Parse default-registry if it exists
        default_registry = document.default_registry
        if default_registry
          dependencies << parse_registry_dependency(registry: default_registry, dependency_file:, is_default: true)
        end

        # Parse registries array if it exists
        document.registries.each do |registry|
          dependencies << parse_registry_dependency(registry:, dependency_file:, is_default: false)
        end

        dependencies.compact
      rescue Dependabot::DependencyFileNotParseable => e
        Dependabot.logger.warn(e.message)
        raise
      end

      # A port's version comes from its `version>=` constraint, the registry baseline, or both.
      # vcpkg installs the lowest version satisfying every constraint, so where both are present
      # the effective version is the higher of the two.
      sig do
        params(
          name: String,
          constraint: T.nilable(String),
          dependency_file: Dependabot::DependencyFile
        )
          .returns(T.nilable(Dependabot::Dependency))
      end
      def build_port_dependency(name:, constraint:, dependency_file:)
        version = effective_port_version(name:, constraint:)

        unless version
          Dependabot.logger.warn("Skipping vcpkg dependency '#{name}' without version>= constraint")
          return nil
        end

        Dependabot::Dependency.new(
          name:,
          version: version.to_s,
          package_manager: "vcpkg",
          requirements: [{
            requirement: constraint && ">=#{constraint}",
            groups: [],
            source: nil,
            file: dependency_file.name
          }]
        )
      end

      sig { params(name: String, constraint: T.nilable(String)).returns(T.nilable(Dependabot::Vcpkg::Version)) }
      def effective_port_version(name:, constraint:)
        constraint_version = constraint && Version.correct?(constraint) ? Version.new(constraint) : nil
        baseline_version = baseline_port_version(name)

        return constraint_version unless baseline_version
        return baseline_version unless constraint_version
        return constraint_version unless constraint_version.comparable_with?(baseline_version)

        [constraint_version, baseline_version].max
      end

      sig { params(name: String).returns(T.nilable(Dependabot::Vcpkg::Version)) }
      def baseline_port_version(name)
        ref = builtin_baseline_ref
        return nil unless ref

        versions_database.baseline_version_for(port: name, ref:)
      end

      # The commit the manifest pins the built-in registry to. Ports resolved from any other
      # registry are left alone, because the versions database shipped with the image only
      # describes the built-in one.
      sig { returns(T.nilable(String)) }
      def builtin_baseline_ref
        manifest_baseline.ref
      end

      sig { returns(Dependabot::Vcpkg::ManifestBaseline) }
      def manifest_baseline
        @manifest_baseline ||= T.let(
          Dependabot::Vcpkg::ManifestBaseline.new(dependency_files:),
          T.nilable(Dependabot::Vcpkg::ManifestBaseline)
        )
      end

      sig { returns(Dependabot::Vcpkg::Package::VersionsDatabase) }
      def versions_database
        @versions_database ||= T.let(
          Dependabot::Vcpkg::Package::VersionsDatabase.new,
          T.nilable(Dependabot::Vcpkg::Package::VersionsDatabase)
        )
      end

      sig do
        params(
          registry: ManifestDocument::Registry,
          dependency_file: Dependabot::DependencyFile,
          is_default: T::Boolean
        )
          .returns(Dependabot::Dependency)
      end
      def parse_registry_dependency(registry:, dependency_file:, is_default: false)
        metadata = { default: is_default }
        metadata[:builtin] = true if registry.builtin

        Dependabot::Dependency.new(
          name: registry.name,
          version: registry.baseline,
          package_manager: "vcpkg",
          requirements: [{
            requirement: nil,
            groups: [],
            source: { type: "git", url: registry.repository, ref: registry.reference },
            file: dependency_file.name
          }],
          metadata: metadata
        )
      end

      # A project relying on a global vcpkg install has no baseline to update.
      # Synthesize one so the updater adds it to the manifest; later runs keep it
      # current. See https://github.com/dependabot/dependabot-core/issues/13051
      sig { returns(T.nilable(Dependabot::Dependency)) }
      def missing_baseline_dependency
        manifest = vcpkg_manifest_file
        return nil unless manifest
        return nil unless manifest_declares_dependencies?(manifest)
        return nil if baseline_resolvable?

        config = vcpkg_configuration_file
        if config.nil?
          synthetic_baseline_dependency(file_name: manifest.name)
        elsif !parsed_document(config)&.default_registry_present?
          synthetic_baseline_dependency(
            file_name: config.name,
            metadata: { default: true, create_default_registry: true }
          )
        end
      end

      sig do
        params(file_name: String, metadata: T::Hash[Symbol, T::Boolean]).returns(Dependabot::Dependency)
      end
      def synthetic_baseline_dependency(file_name:, metadata: {})
        Dependabot::Dependency.new(
          name: VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME,
          version: nil,
          package_manager: "vcpkg",
          requirements: [{
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: VCPKG_DEFAULT_BASELINE_URL,
              ref: VCPKG_DEFAULT_BASELINE_DEFAULT_BRANCH
            },
            file: file_name
          }],
          metadata: metadata
        )
      end

      sig { returns(T::Boolean) }
      def baseline_resolvable?
        manifest_baseline_present? || default_registry_baseline_present?
      end

      sig { returns(T::Boolean) }
      def manifest_baseline_present?
        manifest = vcpkg_manifest_file
        return false unless manifest

        !parsed_document(manifest)&.builtin_baseline.nil?
      end

      sig { returns(T::Boolean) }
      def default_registry_baseline_present?
        config = vcpkg_configuration_file
        return false unless config

        !parsed_document(config)&.default_registry_baseline.nil?
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def manifest_declares_dependencies?(file)
        parsed_document(file)&.dependencies_declared? || false
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def vcpkg_manifest_file
        dependency_files.find { |file| file.name == VCPKG_JSON_FILENAME }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def vcpkg_configuration_file
        dependency_files.find { |file| file.name == VCPKG_CONFIGURATION_JSON_FILENAME }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(ManifestDocument)) }
      def parsed_document(file)
        return nil unless file.content

        ManifestDocument.from_file(file)
      rescue Dependabot::DependencyFileNotParseable
        nil
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager = @package_manager ||= T.let(PackageManager.new, T.nilable(Dependabot::Vcpkg::PackageManager))

      sig { returns(Ecosystem::VersionManager) }
      def language = @language ||= T.let(Language.new, T.nilable(Dependabot::Vcpkg::Language))
    end
  end
end

Dependabot::FileParsers.register("vcpkg", Dependabot::Vcpkg::FileParser)
