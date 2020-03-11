# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/composer/version"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Composer
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      DEPENDENCY_GROUP_KEYS = [
        {
          manifest: "require",
          lockfile: "packages",
          group: "runtime"
        },
        {
          manifest: "require-dev",
          lockfile: "packages-dev",
          group: "development"
        }
      ].freeze

      def parse
        dependency_set = DependencySet.new
        dependency_set += manifest_dependencies
        dependency_set += lockfile_dependencies
        dependency_set.dependencies
      end

      private

      def manifest_dependencies
        dependencies = DependencySet.new

        DEPENDENCY_GROUP_KEYS.each do |keys|
          next unless parsed_composer_json[keys[:manifest]].is_a?(Hash)

          parsed_composer_json[keys[:manifest]].each do |name, req|
            next unless package?(name)

            if lockfile
              version = dependency_version(name: name, type: keys[:group])

              # Ignore dependency versions which don't appear in the
              # composer.lock or are non-numeric and not a git SHA, since they
              # can't be compared later in the process.
              next unless version&.match?(/^\d/) ||
                          version&.match?(/^[0-9a-f]{40}$/)
            end

            dependencies << build_manifest_dependency(name, req, keys)
          end
        end

        dependencies
      end

      def build_manifest_dependency(name, req, keys)
        Dependency.new(
          name: name,
          version: dependency_version(name: name, type: keys[:group]),
          requirements: [{
            requirement: req,
            file: "composer.json",
            source: dependency_source(
              name: name,
              type: keys[:group],
              requirement: req
            ),
            groups: [keys[:group]]
          }],
          package_manager: "composer"
        )
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def lockfile_dependencies
        dependencies = DependencySet.new

        return dependencies unless lockfile

        DEPENDENCY_GROUP_KEYS.each do |keys|
          key = keys.fetch(:lockfile)
          next unless parsed_lockfile[key].is_a?(Array)

          parsed_lockfile[key].each do |details|
            name = details["name"]
            next unless name.is_a?(String) && package?(name)

            version = details["version"]&.to_s&.sub(/^v?/, "")
            next unless version.is_a?(String)
            next unless version.match?(/^\d/) ||
                        version.match?(/^[0-9a-f]{40}$/)

            dependencies << build_lockfile_dependency(name, version, keys)
          end
        end

        dependencies
      end

      # rubocop:enable Metrics/PerceivedComplexity

      def build_lockfile_dependency(name, version, keys)
        Dependency.new(
          name: name,
          version: version,
          requirements: [],
          package_manager: "composer",
          subdependency_metadata: [{
            production: keys.fetch(:group) != "development"
          }]
        )
      end

      def dependency_version(name:, type:)
        return unless lockfile

        package = lockfile_details(name: name, type: type)
        return unless package

        version = package.fetch("version")&.to_s&.sub(/^v?/, "")
        return version unless version&.start_with?("dev-")

        package.dig("source", "reference")
      end

      def dependency_source(name:, type:, requirement:)
        return unless lockfile

        package_details = lockfile_details(name: name, type: type)
        return unless package_details

        if package_details["source"].nil? &&
           package_details.dig("dist", "type") == "path"
          return { type: "path" }
        end

        git_dependency_details(package_details, requirement)
      end

      def git_dependency_details(package_details, requirement)
        return unless package_details.dig("source", "type") == "git"

        branch =
          if requirement.start_with?("dev-")
            requirement.
              sub(/^dev-/, "").
              sub(/\s+as\s.*/, "").
              split("#").first
          elsif package_details.fetch("version")&.to_s&.start_with?("dev-")
            package_details.fetch("version")&.to_s&.sub(/^dev-/, "")
          end

        details = { type: "git", url: package_details.dig("source", "url") }
        return details unless branch

        details.merge(branch: branch, ref: nil)
      end

      def lockfile_details(name:, type:)
        key = lockfile_key(type)
        parsed_lockfile.fetch(key, []).find { |d| d["name"] == name }
      end

      def lockfile_key(type)
        case type
        when "runtime" then "packages"
        when "development" then "packages-dev"
        else raise "unknown type #{type}"
        end
      end

      def package?(name)
        # Filter out php, ext-, composer-plugin-api, and other special
        # packages which don't behave as normal
        name.split("/").count == 2
      end

      def check_required_files
        raise "No composer.json!" unless get_original_file("composer.json")
      end

      def parsed_lockfile
        return unless lockfile

        @parsed_lockfile ||= JSON.parse(lockfile.content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, lockfile.path
      end

      def parsed_composer_json
        @parsed_composer_json ||= JSON.parse(composer_json.content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, composer_json.path
      end

      def composer_json
        @composer_json ||= get_original_file("composer.json")
      end

      def lockfile
        @lockfile ||= get_original_file("composer.lock")
      end
    end
  end
end

Dependabot::FileParsers.register("composer", Dependabot::Composer::FileParser)
