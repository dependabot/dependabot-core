# typed: true
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/swift/file_parser/dependency_parser"
require "dependabot/swift/file_parser/manifest_parser"
require "dependabot/swift/package_manager"
require "dependabot/swift/language"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      def parse
        dependency_set = DependencySet.new

        dependency_parser.parse.map do |dep|
          if dep.top_level?
            source = dep.requirements.first[:source]

            requirements = ManifestParser.new(package_manifest_file, source: source).requirements

            dependency_set << Dependency.new(
              name: dep.name,
              version: dep.version,
              package_manager: dep.package_manager,
              requirements: requirements,
              metadata: dep.metadata
            )
          else
            dependency_set << dep
          end
        end

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(begin
          Ecosystem.new(
            name: ECOSYSTEM,
            language: language,
            package_manager: package_manager
          )
        end, T.nilable(Dependabot::Ecosystem))
      end

      private

      def dependency_parser
        DependencyParser.new(
          dependency_files: dependency_files,
          repo_contents_path: repo_contents_path,
          credentials: credentials
        )
      end

      def check_required_files
        raise "No Package.swift!" unless package_manifest_file
      end

      def package_manifest_file
        # TODO: Select version-specific manifest
        @package_manifest_file ||= get_original_file("Package.swift")
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(T.must(package_manager_version)),
          T.nilable(Dependabot::Swift::PackageManager)
        )
      end

      sig { returns(T.nilable(String)) }
      def package_manager_version
        @package_manager_version ||= T.let(
          begin
            version = SharedHelpers.run_shell_command("swift package --version")
            version.strip.gsub(/Swift Package Manager - Swift \s*/, "")
          end,
          T.nilable(String)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(begin
          Language.new(T.must(swift_version))
        end, T.nilable(Dependabot::Swift::Language))
      end

      sig { returns(T.nilable(String)) }
      def swift_version
        @swift_version ||= T.let(
          begin
            version = SharedHelpers.run_shell_command("swift --version")
            pattern = Dependabot::Ecosystem::VersionManager::DEFAULT_VERSION_PATTERN
            version.match(/Swift version\s*#{pattern}/)&.captures&.first
          end,
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileParsers
  .register("swift", Dependabot::Swift::FileParser)
