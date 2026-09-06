# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/ecosystem"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/kotlin_toolchain/compatibility_profile"
require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/package_manager"
require "dependabot/kotlin_toolchain/wrapper"

module Dependabot
  module KotlinToolchain
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require_relative "file_parser/version_catalog_parser"
      require_relative "file_parser/yaml_dependency_parser"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        package_manager.raise_if_unsupported!
        log_fallback_profile

        dependency_set = DependencySet.new
        dependency_set << wrapper_dependency

        catalog_files.each do |file|
          VersionCatalogParser.new(file: file, profile_name: profile.name).dependencies.each do |dependency|
            dependency_set << dependency
          end
        end

        yaml_files.each do |file|
          YamlDependencyParser.new(file: file, profile: profile).dependencies.each do |dependency|
            dependency_set << dependency
          end
        end

        dependency_set.dependencies
      end

      sig { returns(Dependabot::Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Dependabot::Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          ),
          T.nilable(Dependabot::Ecosystem)
        )
      end

      private

      sig { override.void }
      def check_required_files
        Wrapper.detect_version(dependency_files)
        Wrapper.detect_sha(dependency_files)
        Wrapper.detect_repository(dependency_files)
        has_manifest = yaml_files.any? do |file|
          basename = File.basename(file.name)
          basename == PROJECT_FILE || basename == MODULE_FILE
        end
        unless has_manifest
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "No Kotlin Toolchain project.yaml or module.yaml found"
          )
        end
        return unless catalog_files.length > 1

        raise Dependabot::DependencyFileNotParseable.new(
          T.must(catalog_files.first).name,
          "Kotlin Toolchain supports either libs.versions.toml or gradle/libs.versions.toml, not both"
        )
      end

      sig { returns(Dependabot::Dependency) }
      def wrapper_dependency
        repository = Wrapper.detect_repository(wrapper_files)
        requirements = wrapper_files.map do |file|
          {
            requirement: toolchain_version,
            file: file.name,
            groups: ["toolchain"],
            source: { type: "maven_repo", url: repository },
            metadata: {
              kind: "wrapper",
              repository: repository,
              profile: profile.name
            }
          }
        end

        Dependabot::Dependency.new(
          name: WRAPPER_DEPENDENCY_NAME,
          version: toolchain_version,
          requirements: requirements,
          package_manager: ECOSYSTEM,
          metadata: {
            maven_name: WRAPPER_DEPENDENCY_NAME,
            wrapper: true,
            profile: profile.name
          }
        )
      end

      sig { returns(PackageManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(detected_version: toolchain_version),
          T.nilable(PackageManager)
        )
      end

      sig { returns(CompatibilityProfile) }
      def profile
        @profile ||= T.let(
          CompatibilityProfile.for(toolchain_version),
          T.nilable(CompatibilityProfile)
        )
      end

      sig { returns(String) }
      def toolchain_version
        @toolchain_version ||= T.let(
          Wrapper.detect_version(wrapper_files),
          T.nilable(String)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def wrapper_files
        dependency_files.select { |file| WRAPPER_FILES.include?(File.basename(file.name)) }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def yaml_files
        dependency_files.select do |file|
          basename = File.basename(file.name)
          basename == PROJECT_FILE || basename == MODULE_FILE || file.name.end_with?(MODULE_TEMPLATE_SUFFIX)
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def catalog_files
        dependency_files.select { |file| VERSION_CATALOG_PATHS.include?(file.name) }
      end

      sig { void }
      def log_fallback_profile
        return unless profile.fallback?

        Dependabot.logger.warn(
          "Kotlin Toolchain #{toolchain_version} uses the #{profile.name} compatibility profile; " \
          "unknown settings are skipped"
        )
      end
    end
  end
end

Dependabot::FileParsers.register(
  "kotlin_toolchain",
  Dependabot::KotlinToolchain::FileParser
)
