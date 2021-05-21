# frozen_string_literal: true

require "cgi"
require "excon"
require "nokogiri"
require "open3"
require "yaml"
require "shellwords"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/git_commit_checker"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      def parse
        dependency_set = DependencySet.new

        pins.each do |pin|
          url = pin["repositoryURL"]
          id = Dependabot::Swift::Package::Identifier.new(url)

          version = pin.dig("state", "version")

          requirements = []
          declaration = declarations.find { |d| d["url"] == url }
          declaration&.dig("requirement", "range")&.each do |range|
            if lower_bound = range["lowerBound"]
              requirements << Gem::Requirement.new(">= #{lower_bound}")
            end

            if upper_bound = range["upperBound"]
              requirements << Gem::Requirement.new("< #{upper_bound}")
            end
          end

          if !version.nil? && requirements.empty?
            requirements << Gem::Requirement.new("#{version}")
          end

          dependency_set << Dependency.new(
            name: id.normalized,
            version: version,
            package_manager: "swift",
            requirements: requirements.map do |requirement|
              {
                requirement: requirement.to_s,
                groups: ["dependencies"],
                file: package_manifest_file.name,
                source: {
                  type: "repository",
                  url: url
                }
              }
            end
          )
        end

        dependency_set.dependencies
      end

      private

      def check_required_files
        raise "No Package.swift!" unless package_manifest_file
        raise "No Package.resolved!" unless package_resolved_file
      end

      def declarations
        dump_package(package_manifest_file)["dependencies"]
      end

      def pins
        JSON.parse(package_resolved_file.content).dig("object", "pins")
      end

      def dump_package(manifest)
        SharedHelpers.in_a_temporary_directory do |path|
          File.write(manifest.name, manifest.content)

          command =  Shellwords.join([
            "swift", "package", "dump-package",
            "--skip-update",
            "--package-path", path
          ])

          env = {}
          stdout, _stderr, _status = Open3.capture3(env, command)
          # handle_parser_error(path, stderr) unless status.success?
          JSON.parse(stdout)
        end
      end

      def package_manifest_file
        # TODO: Select version-specific manifest
        @manifest ||= get_original_file("Package.swift")
      end

      def package_resolved_file
        @resolved ||= get_original_file("Package.resolved")
      end
    end
  end
end

Dependabot::FileParsers.
  register("swift", Dependabot::Swift::FileParser)
