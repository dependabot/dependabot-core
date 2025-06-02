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

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /#{VCPKG_JSON_FILENAME}$/o
        ]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        vcpkg_json_file = get_original_file(VCPKG_JSON_FILENAME)
        return [] unless vcpkg_json_file

        return [] unless file_changed?(vcpkg_json_file)

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

        # Find the baseline dependency and update it
        dependencies
          .find { |dep| dep.name == VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME }
          &.then { |dep| update_baseline_in_content(parsed_content, dep, file.name) }

        JSON.pretty_generate(parsed_content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, file.path
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
    end
  end
end

Dependabot::FileUpdaters.register("vcpkg", Dependabot::Vcpkg::FileUpdater)
