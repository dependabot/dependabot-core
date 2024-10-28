# typed: strict
# frozen_string_literal: true

require "dependabot/composer"
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

      DEPENDENCY_GROUP_KEYS = T.let([
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
      ].freeze, T::Array[T::Hash[Symbol, String]])

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = T.let(DependencySet.new, DependencySet)
        dependency_set += manifest_dependencies
        dependency_set += lockfile_dependencies
        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        PackageManager.new(composer_version)
      end

      sig { returns(DependencySet) }
      def manifest_dependencies # rubocop:disable Metrics/PerceivedComplexity
        dependencies = T.let(DependencySet.new, DependencySet)

        DEPENDENCY_GROUP_KEYS.each do |keys|
          manifest = keys[:manifest]
          next unless manifest.is_a?(String)

          next unless parsed_composer_json[manifest].is_a?(Hash)

          parsed_composer_json[manifest].each do |name, req|
            next unless package?(name)

            if lockfile
              group = keys[:group]
              next unless group.is_a?(String)

              version = dependency_version(name: name, type: group)

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

      sig { params(name: String, req: String, keys: T::Hash[Symbol, String]).returns(Dependabot::Dependency) }
      def build_manifest_dependency(name, req, keys)
        group = T.must(keys[:group])

        Dependabot::Dependency.new(
          name: name,
          version: dependency_version(name: name, type: group),
          requirements: [{
            requirement: req,
            file: "composer.json",
            source: dependency_source(
              name: name,
              type: group,
              requirement: req
            ),
            groups: [group]
          }],
          package_manager: "composer"
        )
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(DependencySet) }
      def lockfile_dependencies
        dependencies = T.let(DependencySet.new, DependencySet)

        return dependencies unless lockfile

        DEPENDENCY_GROUP_KEYS.each do |keys|
          key = keys.fetch(:lockfile)
          next unless parsed_lockfile&.[](key).is_a?(Array)

          parsed_lockfile&.[](key)&.each do |details|
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

      sig { params(name: String, version: String, keys: T::Hash[Symbol, String]).returns(Dependabot::Dependency) }
      def build_lockfile_dependency(name, version, keys)
        Dependabot::Dependency.new(
          name: name,
          version: version,
          requirements: [],
          package_manager: "composer",
          subdependency_metadata: [{
            production: keys.fetch(:group) != "development"
          }]
        )
      end

      sig { params(name: String, type: String).returns(T.nilable(String)) }
      def dependency_version(name:, type:)
        return unless lockfile

        package = lockfile_details(name: name, type: type)
        return unless package

        version = package.fetch("version")&.to_s&.sub(/^v?/, "")
        return version unless version&.start_with?("dev-")

        package.dig("source", "reference")
      end

      sig do
        params(name: String, type: String, requirement: String).returns(T.nilable(T::Hash[Symbol, T.nilable(String)]))
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

      sig do
        params(package_details: T::Hash[String, T.untyped],
               requirement: String).returns(T.nilable(T::Hash[Symbol, T.nilable(String)]))
      end
      def git_dependency_details(package_details, requirement)
        return unless package_details.dig("source", "type") == "git"

        branch =
          if requirement.start_with?("dev-")
            requirement
              .sub(/^dev-/, "")
              .sub(/\s+as\s.*/, "")
              .split("#").first
          elsif package_details.fetch("version")&.to_s&.start_with?("dev-")
            package_details.fetch("version")&.to_s&.sub(/^dev-/, "")
          end

        details = { type: "git", url: package_details.dig("source", "url") }
        return details unless branch

        details.merge(branch: branch, ref: nil)
      end

      sig { params(name: String, type: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def lockfile_details(name:, type:)
        key = lockfile_key(type)
        parsed_lockfile&.fetch(key, [])&.find { |d| d["name"] == name }
      end

      sig { params(type: String).returns(String) }
      def lockfile_key(type)
        case type
        when "runtime" then "packages"
        when "development" then "packages-dev"
        else raise "unknown type #{type}"
        end
      end

      sig { params(name: String).returns(T::Boolean) }
      def package?(name)
        name.split("/").count == 2
      end

      sig { override.void }
      def check_required_files
        raise "No composer.json!" unless get_original_file("composer.json")
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def parsed_lockfile # rubocop:disable Metrics/PerceivedComplexity
        return unless lockfile

        content = lockfile&.content

        raise Dependabot::DependencyFileNotParseable, lockfile&.path || "" if content.nil? || content.strip.empty?

        @parsed_lockfile ||= T.let(JSON.parse(content), T.nilable(T::Hash[String, T.untyped]))
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, lockfile&.path || ""
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_composer_json
        content = composer_json&.content

        raise Dependabot::DependencyFileNotParseable, composer_json&.path || "" if content.nil? || content.strip.empty?

        @parsed_composer_json ||= T.let(JSON.parse(content), T.nilable(T::Hash[String, T.untyped]))
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, composer_json&.path || ""
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def composer_json
        @composer_json ||= T.let(get_original_file("composer.json"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(get_original_file("composer.lock"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(String) }
      def composer_version
        @composer_version ||= T.let(Helpers.composer_version(parsed_composer_json, parsed_lockfile), T.nilable(String))
      end
    end
  end
end

Dependabot::FileParsers.register("composer", Dependabot::Composer::FileParser)
