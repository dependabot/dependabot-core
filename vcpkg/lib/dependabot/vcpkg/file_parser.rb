# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

require "dependabot/vcpkg"
require "dependabot/vcpkg/dependency"
require "dependabot/vcpkg/language"
require "dependabot/vcpkg/package_manager"

module Dependabot
  module Vcpkg
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dependency_files.filter_map { |file| parse_dependency_file(file) }
                        .each { |dependency| dependency_set << dependency }

        dependency_set.dependencies
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
        return if dependency_files.any? { |f| f.name == VCPKG_JSON_FILENAME }

        raise Dependabot::DependencyFileNotFound, VCPKG_JSON_FILENAME
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::Dependency)) }
      def parse_dependency_file(dependency_file)
        return unless dependency_file.content

        case dependency_file.name
        when VCPKG_JSON_FILENAME then parse_vcpkg_json(dependency_file)
        when VCPKG_CONFIGURATION_JSON_FILENAME then nil # TODO
        end
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::Dependency)) }
      def parse_vcpkg_json(dependency_file)
        contents = T.must(dependency_file.content)

        parsed_json = JSON.parse(contents)
        baseline = parsed_json["builtin-baseline"]
        return unless baseline

        build_baseline_dependency(baseline: baseline, file: dependency_file)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, T.must(dependency_files.first).path
      end

      sig { params(baseline: String, file: Dependabot::DependencyFile).returns(Dependabot::Dependency) }
      def build_baseline_dependency(baseline:, file:)
        Dependabot::Vcpkg::Dependency.new(
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
            file: file.name
          }]
        )
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(PackageManager.new, T.nilable(Dependabot::Vcpkg::PackageManager))
      end

      sig { returns(Ecosystem::VersionManager) }
      def language
        @language ||= T.let(Language.new, T.nilable(Dependabot::Vcpkg::Language))
      end
    end
  end
end

Dependabot::FileParsers.register("vcpkg", Dependabot::Vcpkg::FileParser)
