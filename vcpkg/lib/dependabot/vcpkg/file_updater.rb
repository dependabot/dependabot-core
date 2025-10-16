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
        vcpkg_json_file = get_original_file(VCPKG_JSON_FILENAME)
        return [] unless vcpkg_json_file&.then { |file| file_changed?(file) }

        [updated_file(
          file: vcpkg_json_file,
          content: updated_vcpkg_json_content(vcpkg_json_file)
        )]
      end

      private

      sig { override.void }
      def check_required_files
        return if get_original_file(VCPKG_JSON_FILENAME)

        raise Dependabot::DependencyFileNotFound, VCPKG_JSON_FILENAME
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
        # Find the requirement for this specific file
        requirement = dependency.requirements.find { |r| r[:file] == filename }
        return unless requirement

        # Extract and validate the new baseline
        case requirement[:source]
        in { ref: String => new_baseline }
          content["builtin-baseline"] = new_baseline
        else
          # Skip if source doesn't have the expected structure
        end
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
    end
  end
end

Dependabot::FileUpdaters.register("vcpkg", Dependabot::Vcpkg::FileUpdater)
