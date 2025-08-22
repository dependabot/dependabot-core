# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/logger"

require "dependabot/vcpkg"
require "dependabot/vcpkg/language"
require "dependabot/vcpkg/package_manager"

module Dependabot
  module Vcpkg
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_files.flat_map { |file| parse_dependency_file(file) }.compact
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

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_dependency_file(dependency_file)
        return [] unless dependency_file.content

        case dependency_file.name
        in VCPKG_JSON_FILENAME then parse_vcpkg_json(dependency_file)
        in VCPKG_CONFIGURATION_JSON_FILENAME then [] # TODO
        else []
        end
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_vcpkg_json(dependency_file)
        contents = T.must(dependency_file.content)
        parsed_json = JSON.parse(contents)

        dependencies = []

        parsed_json["builtin-baseline"]&.then do |baseline|
          dependencies << parse_baseline_dependency(baseline:, dependency_file:)
        end

        parsed_json["dependencies"]&.each do |dep|
          dependency = parse_port_dependency(dep:, dependency_file:)
          dependencies << dependency if dependency
        end

        dependencies.compact
      rescue JSON::ParserError
        Dependabot.logger.warn("Failed to parse #{dependency_file.name}: #{dependency_file.content}")
        raise Dependabot::DependencyFileNotParseable, T.must(dependency_files.first).path
      end

      sig { params(baseline: String, dependency_file: Dependabot::DependencyFile).returns(Dependabot::Dependency) }
      def parse_baseline_dependency(baseline:, dependency_file:)
        Dependabot::Dependency.new(
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

      sig do
        params(
          dep: T.untyped,
          dependency_file: Dependabot::DependencyFile
        )
          .returns(T.nilable(Dependabot::Dependency))
      end
      def parse_port_dependency(dep:, dependency_file:)
        case dep
        when String
          # Simple string dependency like "curl" - log and skip
          Dependabot.logger.warn("Skipping vcpkg dependency '#{dep}' without version>= constraint")
          nil
        when Hash
          name = dep["name"]
          version_constraint = dep["version>="]

          return nil unless name.is_a?(String)

          unless version_constraint
            Dependabot.logger.warn("Skipping vcpkg dependency '#{name}' without version>= constraint")
            return nil
          end

          # Parse version and optional port-version
          version, _port_version = parse_version_with_port(version_constraint)

          Dependabot::Dependency.new(
            name:,
            version:,
            package_manager: "vcpkg",
            requirements: [{
              requirement: ">=#{version_constraint}",
              groups: [],
              source: nil,
              file: dependency_file.name
            }]
          )
        else
          Dependabot.logger.warn("Skipping unknown vcpkg dependency format: #{dep.inspect}")
          nil
        end
      end

      sig { params(version_string: String).returns([String, T.nilable(String)]) }
      def parse_version_with_port(version_string)
        if version_string.include?("#")
          version_string.split("#", 2).then { |parts| [parts[0] || "", parts[1]] }
        else
          [version_string, nil]
        end
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager = @package_manager ||= T.let(PackageManager.new, T.nilable(Dependabot::Vcpkg::PackageManager))

      sig { returns(Ecosystem::VersionManager) }
      def language = @language ||= T.let(Language.new, T.nilable(Dependabot::Vcpkg::Language))
    end
  end
end

Dependabot::FileParsers.register("vcpkg", Dependabot::Vcpkg::FileParser)
