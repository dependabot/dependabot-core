# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/vcpkg"

module Dependabot
  module Vcpkg
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        # Handle vcpkg.json
        vcpkg_json_file = get_original_file(VCPKG_JSON_FILENAME)
        if vcpkg_json_file&.then { |file| file_changed?(file) }
          updated_files << updated_file(
            file: vcpkg_json_file,
            content: updated_vcpkg_json_content(vcpkg_json_file)
          )
        end

        # Handle vcpkg-configuration.json
        vcpkg_config_file = get_original_file(VCPKG_CONFIGURATION_JSON_FILENAME)
        if vcpkg_config_file&.then { |file| file_changed?(file) }
          updated_files << updated_file(
            file: vcpkg_config_file,
            content: updated_vcpkg_configuration_json_content(vcpkg_config_file)
          )
        end

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        return if get_original_file(VCPKG_JSON_FILENAME) || get_original_file(VCPKG_CONFIGURATION_JSON_FILENAME)

        raise Dependabot::DependencyFileNotFound.new(nil, "No vcpkg manifest files found")
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_vcpkg_json_content(file)
        content = T.must(file.content)
        parsed_content = JSON.parse(content)

        dependencies
          .filter_map { |dep| [dep, dep.requirements.find { |r| r[:file] == file.name }] }
          .select { |_, requirement| requirement }
          .each { |dependency, _| update_dependency_in_content(parsed_content, dependency, file.name) }

        JSON.pretty_generate(parsed_content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_vcpkg_configuration_json_content(file)
        content = T.must(file.content)
        parsed_content = JSON.parse(content)

        dependencies
          .filter_map { |dep| [dep, dep.requirements.find { |r| r[:file] == file.name }] }
          .select { |_, requirement| requirement }
          .each { |dependency, _| update_registry_dependency_in_content(parsed_content, dependency, file.name) }

        JSON.pretty_generate(parsed_content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_dependency_in_content(content, dependency, filename)
        case dependency.name
        when VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME
          update_baseline_in_content(content, dependency, filename)
        else
          update_port_dependency_in_content(content, dependency)
        end
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_baseline_in_content(content, dependency, filename)
        update_baseline_field(content, dependency, filename, "builtin-baseline")
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency).void }
      def update_port_dependency_in_content(content, dependency)
        # Update the dependencies array
        dependencies_array = content["dependencies"]
        return unless dependencies_array.is_a?(Array)

        # Find and update the specific dependency using more functional approach
        target_dep = dependencies_array.find { _1.is_a?(Hash) && _1["name"] == dependency.name }
        target_dep&.[]=("version>=", dependency.version)
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_registry_dependency_in_content(content, dependency, filename)
        # Check if this is a default registry update based on metadata
        if dependency.metadata[:default]
          update_default_registry(content, dependency, filename)
        else
          # For registries array, find by repository URL
          update_registry_by_name(content, dependency, filename)
        end
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_default_registry(content, dependency, filename)
        default_registry = content["default-registry"]
        return unless default_registry.is_a?(Hash)

        update_baseline_field(default_registry, dependency, filename, "baseline")
      end

      sig { params(content: T::Hash[String, T.untyped], dependency: Dependabot::Dependency, filename: String).void }
      def update_registry_by_name(content, dependency, filename)
        registries = content["registries"]
        return unless registries.is_a?(Array)

        # Find registry based on dependency characteristics
        registry = find_target_registry(registries, dependency)
        return unless registry

        update_baseline_field(registry, dependency, filename, "baseline")
      end

      sig do
        params(
          target: T::Hash[String, T.untyped],
          dependency: Dependabot::Dependency,
          filename: String,
          field_name: String
        ).void
      end
      def update_baseline_field(target, dependency, filename, field_name)
        # Find the requirement for this specific file
        requirement = dependency.requirements.find { |r| r[:file] == filename }
        return unless requirement

        # Extract and validate the new baseline
        case requirement[:source]
        in { ref: String => new_baseline }
          target[field_name] = new_baseline
        else
          # Skip if source doesn't have the expected structure
        end
      end

      sig do
        params(
          registries: T::Array[T.untyped],
          dependency: Dependabot::Dependency
        )
          .returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def find_target_registry(registries, dependency)
        if dependency.metadata[:builtin]
          # For builtin registries, find by kind
          registries.find { |r| r.is_a?(Hash) && r["kind"] == "builtin" }
        else
          # For git registries, find by repository URL
          repository_url = dependency.requirements.first&.dig(:source, :url)
          registries.find { |r| r.is_a?(Hash) && r["repository"] == repository_url }
        end
      end
    end
  end
end

Dependabot::FileUpdaters.register("vcpkg", Dependabot::Vcpkg::FileUpdater)
