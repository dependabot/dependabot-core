# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"

require "dependabot/vcpkg"
require "dependabot/vcpkg/manifest_document"

module Dependabot
  module Vcpkg
    # Finds the commit a manifest pins the built-in registry to.
    #
    # This ignores any other registry, because the versions database shipped with the updater image
    # only describes the built-in one.
    class ManifestBaseline
      extend T::Sig

      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
      def initialize(dependency_files:)
        @dependency_files = dependency_files
        @ref = T.let(nil, T.nilable(String))
        @resolved = T.let(false, T::Boolean)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T.nilable(String)) }
      def ref
        return @ref if @resolved

        @resolved = true
        @ref = manifest_builtin_baseline || default_registry_builtin_baseline
      end

      # The file the baseline lives in, and the JSON path to it, so an updater knows what to
      # rewrite.
      sig { returns(T.nilable([String, T::Array[String]])) }
      def location
        return [T.must(vcpkg_manifest_file).name, [VCPKG_BUILTIN_BASELINE_KEY]] if manifest_builtin_baseline
        return nil unless default_registry_builtin_baseline

        [T.must(vcpkg_configuration_file).name, %w(default-registry baseline)]
      end

      private

      sig { returns(T.nilable(String)) }
      def manifest_builtin_baseline
        manifest = vcpkg_manifest_file
        return nil unless manifest

        parsed_document(manifest)&.builtin_baseline
      rescue Dependabot::DependencyFileNotParseable
        nil
      end

      sig { returns(T.nilable(String)) }
      def default_registry_builtin_baseline
        config = vcpkg_configuration_file
        return nil unless config

        document = parsed_document(config)
        return nil unless document && builtin_registry?(document)

        document.default_registry_baseline
      rescue Dependabot::DependencyFileNotParseable
        nil
      end

      sig { params(document: ManifestDocument).returns(T::Boolean) }
      def builtin_registry?(document)
        return true if document.default_registry_kind == "builtin"
        return false unless document.default_registry_kind == "git"

        repository = document.default_registry_repository
        return false unless repository

        official = [VCPKG_DEFAULT_REGISTRY_REPOSITORY, VCPKG_DEFAULT_BASELINE_URL]
        official.include?(repository.delete_suffix("/"))
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
    end
  end
end
