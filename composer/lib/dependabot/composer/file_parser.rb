# typed: strong
# frozen_string_literal: true

require "dependabot/composer"
require "dependabot/dependency"
require "dependabot/composer/version"
require "dependabot/composer/manifest_document"
require "dependabot/composer/lockfile_document"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Composer
    REQUIREMENT_SEPARATOR = /
      (?<=\S|^)          # Positive lookbehind for a non-whitespace character or start of string
      (?:[ \t,]*\|\|?[ \t]*) # Match optional whitespace, a pipe (|| or |), and optional whitespace
      (?=\S|$)           # Positive lookahead for a non-whitespace character or end of string
    /x

    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      DEPENDENCY_GROUP_KEYS = T.let(
        [
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
        ].freeze,
        T::Array[T::Hash[Symbol, String]]
      )

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
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        if composer_version == Helpers::V1
          return PackageManager.new(
            detected_version: composer_version
          )
        end
        PackageManager.new(
          detected_version: composer_version,
          raw_version: env_versions[:composer]
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        php_version = env_versions[:php]

        return unless php_version

        Language.new(
          php_version,
          requirement: php_requirement
        )
      end

      sig { returns(T::Hash[Symbol, T.nilable(String)]) }
      def env_versions
        @env_versions ||= T.let(
          Helpers.fetch_composer_and_php_versions,
          T.nilable(T::Hash[Symbol, T.nilable(String)])
        )
      end

      # Capture PHP requirement from the composer.json
      sig { returns(T.nilable(Requirement)) }
      def php_requirement
        requirement_string = Helpers.php_constraint(manifest_document)

        return nil unless requirement_string

        requirements = requirement_string
                       .strip
                       .split(REQUIREMENT_SEPARATOR)
                       .map(&:strip)
                       .reject(&:empty?)

        return nil unless requirements.any?

        Requirement.new(requirements)
      end

      sig { returns(DependencySet) }
      def manifest_dependencies # rubocop:disable Metrics/PerceivedComplexity
        dependencies = T.let(DependencySet.new, DependencySet)

        DEPENDENCY_GROUP_KEYS.each do |keys|
          manifest = keys[:manifest]
          next unless manifest.is_a?(String)

          manifest_document.requirements(manifest).each do |entry|
            name = entry.name
            next unless package?(name)

            req = entry.string_requirement
            local_package_prefix = ["dev-main", "dev-master", "@dev"]

            # we avoid updating local packages, so we skip them adding to dependency list
            if req && local_package_prefix.include?(req)
              Dependabot.logger.info("Skipping #{name} with version #{req} as it cannot be updated.")
              next
            end

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

            dependencies << build_manifest_dependency(name, entry.requirement, keys)
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
            file: PackageManager::MANIFEST_FILENAME,
            source: dependency_source(
              name: name,
              type: group,
              requirement: req
            ),
            groups: [group]
          }],
          package_manager: PackageManager::NAME
        )
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(DependencySet) }
      def lockfile_dependencies
        dependencies = T.let(DependencySet.new, DependencySet)

        return dependencies unless lockfile

        DEPENDENCY_GROUP_KEYS.each do |keys|
          key = keys.fetch(:lockfile)
          lockfile_document&.packages(key)&.each do |details|
            name = details.name
            next unless name && package?(name)

            version = details.version&.sub(/^v?/, "")
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
          package_manager: PackageManager::NAME,
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

        version = package.required_version&.sub(/^v?/, "")
        return version unless version&.start_with?("dev-")

        package.source_reference
      end

      sig do
        params(
          name: String,
          type: String,
          requirement: String
        ).returns(T.nilable(Dependabot::DependencyRequirement::ObjectHash))
      end
      def dependency_source(name:, type:, requirement:)
        return unless lockfile

        package_details = lockfile_details(name: name, type: type)
        return unless package_details

        return { type: "path" } if package_details.path_source?

        git_dependency_details(package_details, requirement)
      end

      sig do
        params(
          package_details: LockfileDocument::PackageRecord,
          requirement: String
        ).returns(T.nilable(Dependabot::DependencyRequirement::ObjectHash))
      end
      def git_dependency_details(package_details, requirement)
        details = package_details.git_source
        return unless details

        branch =
          if requirement.start_with?("dev-")
            requirement
              .sub(/^dev-/, "")
              .sub(/\s+as\s.*/, "")
              .split("#").first
          elsif package_details.required_version&.start_with?("dev-")
            package_details.required_version&.sub(/^dev-/, "")
          end

        return details unless branch

        details.merge(branch: branch, ref: nil)
      end

      sig { params(name: String, type: String).returns(T.nilable(LockfileDocument::PackageRecord)) }
      def lockfile_details(name:, type:)
        key = lockfile_key(type)
        lockfile_document&.find_package(key, name)
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
        raise "No #{PackageManager::MANIFEST_FILENAME}!" unless get_original_file(PackageManager::MANIFEST_FILENAME)
      end

      sig { returns(T.nilable(LockfileDocument)) }
      def lockfile_document # rubocop:disable Metrics/PerceivedComplexity
        return unless lockfile

        content = lockfile&.content

        raise Dependabot::DependencyFileNotParseable, lockfile&.path || "" if content.nil? || content.strip.empty?

        @lockfile_document ||= T.let(LockfileDocument.from_file(T.must(lockfile)), T.nilable(LockfileDocument))
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, lockfile&.path || ""
      end

      sig { returns(ManifestDocument) }
      def manifest_document
        content = composer_json&.content

        if content.nil? || content.strip.empty?
          raise Dependabot::DependencyFileNotParseable,
                composer_json&.path || ""
        end

        @manifest_document ||= T.let(ManifestDocument.from_file(T.must(composer_json)), T.nilable(ManifestDocument))
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, composer_json&.path || ""
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def composer_json
        @composer_json ||= T.let(
          get_original_file(PackageManager::MANIFEST_FILENAME),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          get_original_file(PackageManager::LOCKFILE_FILENAME),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(String) }
      def composer_version
        @composer_version ||= T.let(
          Helpers.composer_version(manifest_document, lockfile_document),
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileParsers.register("composer", Dependabot::Composer::FileParser)
