# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/swift/file_parser/dependency_parser"
require "dependabot/swift/file_parser/manifest_parser"

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
              requirements: requirements
            )
          else
            dependency_set << dep
          end
        end

        dependency_set.dependencies
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
    end
  end
end

Dependabot::FileParsers.
  register("swift", Dependabot::Swift::FileParser)
