# frozen_string_literal: true

require "json"
require "yaml"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/pub/requirement"
require "dependabot/pub/version"

module Dependabot
  module Pub
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      def latest_version
        return latest_version_for_hosted_dependency if hosted_dependency?
        # Other sources (git or path dependencies) just return `nil`
      end

      def latest_resolvable_version
        version = latest_resolvable_version_for_hosted_dependency if hosted_dependency?

        return version unless version == dependency.version
        # Other sources (git, path dependencies) just return `nil`
      end

      def latest_resolvable_version_with_no_unlock
        latest_resolvable_version
      end

      def updated_requirements
        # We just return the original requirements here as the file updater does
        # not rely on it, but rather uses the offical Dart Pub CLI to update
        # dependencies.
        dependency.requirements
      end

      def requirement_class
        Requirement
      end

      def version_class
        Version
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # TODO: consider if multi version updates are easily doable with `dart pub outdated`.
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def latest_version_for_hosted_dependency
        return unless hosted_dependency?

        return @latest_version_for_hosted_dependency if @latest_version_for_hosted_dependency

        versions = hosted_package_versions

        @latest_version_for_hosted_dependency = version_class.new(versions["latest"]["version"])
      end

      def latest_resolvable_version_for_hosted_dependency
        return unless hosted_dependency?

        return @latest_resolvable_version_for_hosted_dependency if @latest_resolvable_version_for_hosted_dependency

        versions = hosted_package_versions

        @latest_resolvable_version_for_hosted_dependency = version_class.new(versions["upgradable"]["version"])
      end

      def hosted_package_versions
        packages = packages_information["packages"]
        package = packages.find { |p| p["package"] == dependency.name }
        package
      end

      def hosted_dependency?
        return false if dependency_source_details.nil?

        dependency_source_details.fetch(:type) == "hosted"
      end

      def dependency_source_details
        sources =
          dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

        raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

        sources.first
      end

      def packages_information
        # TODO: Cache this information somehow for other dependencies.
        SharedHelpers.in_a_temporary_directory do
          File.write(pubspec_files.fetch(:yaml).name, pubspec_files.fetch(:yaml).content)
          File.write(pubspec_files.fetch(:lock).name, pubspec_files.fetch(:lock).content)

          SharedHelpers.with_git_configured(credentials: credentials) do
            # TODO: Use Flutter tool for Flutter projects
            # TODO: Add CI=true and PUB_ENVIRONMENT=dependabot
            output = SharedHelpers.run_shell_command("dart pub outdated --show-all --json")
            result = JSON.parse(output)
            result
          end
        end
      end

      def pubspec_files
        pubspec_file_pairs.first
      end

      def pubspec_file_pairs
        pairs = []
        pubspec_yaml_files.each do |f|
          lock_file = pubspec_lock_files.find { |l| f.directory == l.directory }
          next unless lock_file

          pairs << {
            yaml: f,
            lock: lock_file
          }
        end
        pairs
      end

      def pubspec_yaml_files
        dependency_files.select { |f| f.name.end_with?("pubspec.yaml") }
      end

      def pubspec_lock_files
        dependency_files.select { |f| f.name.end_with?("pubspec.lock") }
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("pub", Dependabot::Pub::UpdateChecker)
