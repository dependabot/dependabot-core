# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_file"

require "dependabot/vcpkg"

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

        baseline = parsed_json(manifest)&.dig(VCPKG_BUILTIN_BASELINE_KEY)
        baseline.is_a?(String) ? baseline : nil
      end

      sig { returns(T.nilable(String)) }
      def default_registry_builtin_baseline
        registry = default_registry
        return nil unless registry
        return nil unless builtin_registry?(registry)

        baseline = registry["baseline"]
        baseline.is_a?(String) ? baseline : nil
      end

      sig { returns(T.nilable(T::Hash[String, Object])) }
      def default_registry
        config = vcpkg_configuration_file
        return nil unless config

        registry = parsed_json(config)&.dig("default-registry")
        registry.is_a?(Hash) ? registry : nil
      end

      sig { params(registry: T::Hash[String, Object]).returns(T::Boolean) }
      def builtin_registry?(registry)
        return true if registry["kind"] == "builtin"
        return false unless registry["kind"] == "git"

        repository = registry["repository"]
        return false unless repository.is_a?(String)

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

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(T::Hash[String, Object])) }
      def parsed_json(file)
        content = file.content
        return nil unless content

        parsed = JSON.parse(content)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end
    end
  end
end
