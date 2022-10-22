# frozen_string_literal: true

require "cocoapods"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/cocoapods/file_updater"
require "dependabot/cocoapods/update_checker/requirements_updater"

module Dependabot
  module CocoaPods
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      def latest_version
        # TODO: Add shortcut to get latest version
        latest_resolvable_version
      end

      def latest_resolvable_version
        @latest_resolvable_version ||= fetch_latest_resolvable_version
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          existing_version: dependency.version,
          latest_version: latest_version&.to_s,
          latest_resolvable_version: latest_resolvable_version&.to_s
        ).updated_requirements
      end

      def latest_resolvable_version_with_no_unlock
        return latest_resolvable_version unless dependency.top_level?

        return latest_resolvable_version_with_no_unlock_for_git_dependency if git_dependency?

        latest_version_finder.latest_version_with_no_unlock
      end

      private

      def fetch_latest_resolvable_version
        parsed_file = Pod::Podfile.from_ruby(nil, podfile.content)
        pod = parsed_file.dependencies.find { |d| d.name == dependency.name }

        return nil if pod.external_source

        specs = pod_analyzer.analyze.specifications

        Pod::Version.new(specs.find { |d| d.name == dependency.name }.version)
      end

      def latest_version_resolvable_with_full_unlock?
        return unless latest_version

        # No support for full unlocks for subdependencies yet
        return false unless dependency.top_level?

        version_resolver.latest_version_resolvable_with_full_unlock?
      end

      def updated_dependencies_after_full_unlock
        version_resolver.dependency_updates_from_full_unlock.
          map { |update_details| build_updated_dependency(update_details) }
      end

      def pod_analyzer
        @pod_analyzer =
          begin
            lockfile_hash =
              Pod::YAMLHelper.load_string(lockfile_for_update_check)
            parsed_lockfile = Pod::Lockfile.new(lockfile_hash)

            evaluated_podfile =
              Pod::Podfile.from_ruby(nil, podfile_for_update_check)

            pod_sandbox = Pod::Sandbox.new("tmp")

            analyzer = Pod::Installer::Analyzer.new(
              pod_sandbox,
              evaluated_podfile,
              parsed_lockfile,
              nil,
              true,
              { pods: [dependency.name] }
            )

            analyzer.installation_options.integrate_targets = false

            analyzer.config.silent = true
            analyzer.update_repositories

            analyzer
          end
      end

      def lockfile
        lockfile = dependency_files.find { |f| f.name == "Podfile.lock" }
        raise "No Podfile.lock!" unless lockfile

        lockfile
      end

      def podfile
        podfile = dependency_files.find { |f| f.name == "Podfile" }
        raise "No Podfile!" unless podfile

        podfile
      end

      def podfile_for_update_check
        content = remove_dependency_requirement(podfile.content)
        replace_ssh_links_with_https(content)
      end

      def lockfile_for_update_check
        replace_ssh_links_with_https(lockfile.content)
      end

      # Replace the original pod requirements with nothing, to fully "unlock"
      # the pod during version checking
      def remove_dependency_requirement(podfile_content)
        regex = Dependabot::CocoaPods::FileUpdater::POD_CALL

        podfile_content.
          to_enum(:scan, regex).
          find { Regexp.last_match[:name] == dependency.name }

        original_pod_declaration_string = Regexp.last_match.to_s
        updated_pod_declaration_string =
          original_pod_declaration_string.
          sub(/,[ \t]*#{Dependabot::CocoaPods::FileUpdater::REQUIREMENTS}/, "")

        podfile_content.gsub(
          original_pod_declaration_string,
          updated_pod_declaration_string
        )
      end

      def replace_ssh_links_with_https(content)
        content.gsub("git@github.com:", "https://github.com/")
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("cocoapods", Dependabot::CocoaPods::UpdateChecker)
