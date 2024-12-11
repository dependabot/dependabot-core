# typed: strong
# frozen_string_literal: true

require "shellwords"
require "sorbet-runtime"

require_relative "nuget_config_credential_helpers"

module Dependabot
  module Nuget
    module NativeHelpers
      extend T::Sig

      sig { returns(String) }
      def self.native_helpers_root
        helpers_root = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)
        return File.join(helpers_root, "nuget") unless helpers_root.nil?

        File.expand_path("../../../helpers", __dir__)
      end

      sig { params(project_tfms: T::Array[String], package_tfms: T::Array[String]).returns(T::Boolean) }
      def self.run_nuget_framework_check(project_tfms, package_tfms)
        exe_path = File.join(native_helpers_root, "NuGetUpdater", "NuGetUpdater.Cli")
        command_parts = [
          exe_path,
          "framework-check",
          "--project-tfms",
          *project_tfms,
          "--package-tfms",
          *package_tfms
        ]
        command = Shellwords.join(command_parts)

        fingerprint = [
          exe_path,
          "framework-check",
          "--project-tfms",
          "<project-tfms>",
          "--package-tfms",
          "<package-tfms>"
        ].join(" ")

        puts "running NuGet updater:\n" + command

        output = SharedHelpers.run_shell_command(command, allow_unsafe_shell_command: true, fingerprint: fingerprint)
        puts output

        # Exit code == 0 means that all project frameworks are compatible
        true
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed
        # Exit code != 0 means that not all project frameworks are compatible
        false
      end

      sig do
        params(
          job_path: String,
          repo_root: String,
          workspace_path: String,
          output_path: String
        ).returns([String, String])
      end
      def self.get_nuget_discover_tool_command(job_path:, repo_root:, workspace_path:, output_path:)
        exe_path = File.join(native_helpers_root, "NuGetUpdater", "NuGetUpdater.Cli")
        command_parts = [
          exe_path,
          "discover",
          "--job-path",
          job_path,
          "--repo-root",
          repo_root,
          "--workspace",
          workspace_path,
          "--output",
          output_path
        ].compact

        command = Shellwords.join(command_parts)

        fingerprint = [
          exe_path,
          "discover",
          "--job-path",
          "<job-path>",
          "--repo-root",
          "<repo-root>",
          "--workspace",
          "<path-to-workspace>",
          "--output",
          "<path-to-output>"
        ].compact.join(" ")

        [command, fingerprint]
      end

      sig do
        params(
          job_path: String,
          repo_root: String,
          workspace_path: String,
          output_path: String,
          credentials: T::Array[Dependabot::Credential]
        ).void
      end
      def self.run_nuget_discover_tool(job_path:, repo_root:, workspace_path:, output_path:, credentials:)
        (command, fingerprint) = get_nuget_discover_tool_command(job_path: job_path,
                                                                 repo_root: repo_root,
                                                                 workspace_path: workspace_path,
                                                                 output_path: output_path)

        puts "running NuGet discovery:\n" + command

        NuGetConfigCredentialHelpers.patch_nuget_config_for_action(credentials) do
          output = SharedHelpers.run_shell_command(command, allow_unsafe_shell_command: true, fingerprint: fingerprint)
          puts output
        end
      end

      sig do
        params(job_path: String, repo_root: String, discovery_file_path: String, dependency_file_path: String,
               analysis_folder_path: String).returns([String, String])
      end
      def self.get_nuget_analyze_tool_command(job_path:, repo_root:, discovery_file_path:, dependency_file_path:,
                                              analysis_folder_path:)
        exe_path = File.join(native_helpers_root, "NuGetUpdater", "NuGetUpdater.Cli")
        command_parts = [
          exe_path,
          "analyze",
          "--job-path",
          job_path,
          "--repo-root",
          repo_root,
          "--discovery-file-path",
          discovery_file_path,
          "--dependency-file-path",
          dependency_file_path,
          "--analysis-folder-path",
          analysis_folder_path
        ].compact

        command = Shellwords.join(command_parts)

        fingerprint = [
          exe_path,
          "analyze",
          "--job-path",
          "<job-path>",
          "--discovery-file-path",
          "<discovery-file-path>",
          "--dependency-file-path",
          "<dependency-file-path>",
          "--analysis-folder-path",
          "<analysis_folder_path>"
        ].compact.join(" ")

        [command, fingerprint]
      end

      sig do
        params(
          job_path: String, repo_root: String, discovery_file_path: String, dependency_file_path: String,
          analysis_folder_path: String, credentials: T::Array[Dependabot::Credential]
        ).void
      end
      def self.run_nuget_analyze_tool(job_path:, repo_root:, discovery_file_path:, dependency_file_path:,
                                      analysis_folder_path:, credentials:)
        (command, fingerprint) = get_nuget_analyze_tool_command(job_path: job_path,
                                                                repo_root: repo_root,
                                                                discovery_file_path: discovery_file_path,
                                                                dependency_file_path: dependency_file_path,
                                                                analysis_folder_path: analysis_folder_path)

        puts "running NuGet analyze:\n" + command

        NuGetConfigCredentialHelpers.patch_nuget_config_for_action(credentials) do
          output = SharedHelpers.run_shell_command(command, allow_unsafe_shell_command: true, fingerprint: fingerprint)
          puts output
        end
      end

      # rubocop:disable Metrics/MethodLength
      sig do
        params(job_path: String, repo_root: String, proj_path: String, dependency: Dependency,
               is_transitive: T::Boolean, result_output_path: String).returns([String, String])
      end
      def self.get_nuget_updater_tool_command(job_path:, repo_root:, proj_path:, dependency:, is_transitive:,
                                              result_output_path:)
        exe_path = File.join(native_helpers_root, "NuGetUpdater", "NuGetUpdater.Cli")
        command_parts = [
          exe_path,
          "update",
          "--job-path",
          job_path,
          "--repo-root",
          repo_root,
          "--solution-or-project",
          proj_path,
          "--dependency",
          dependency.name,
          "--new-version",
          dependency.version,
          "--previous-version",
          dependency.previous_version,
          is_transitive ? "--transitive" : nil,
          "--result-output-path",
          result_output_path
        ].compact

        command = Shellwords.join(command_parts)

        fingerprint = [
          exe_path,
          "update",
          "--job-path",
          "<job-path>",
          "--repo-root",
          "<repo-root>",
          "--solution-or-project",
          "<path-to-solution-or-project>",
          "--dependency",
          "<dependency-name>",
          "--new-version",
          "<new-version>",
          "--previous-version",
          "<previous-version>",
          is_transitive ? "--transitive" : nil,
          "--result-output-path",
          "<result-output-path>"
        ].compact.join(" ")

        [command, fingerprint]
      end
      # rubocop:enable Metrics/MethodLength

      sig { returns(String) }
      def self.update_result_file_path
        File.join(Dir.tmpdir, "update-result.json")
      end

      sig do
        params(
          job_path: String,
          repo_root: String,
          proj_path: String,
          dependency: Dependency,
          is_transitive: T::Boolean,
          credentials: T::Array[Dependabot::Credential]
        ).void
      end
      def self.run_nuget_updater_tool(job_path:, repo_root:, proj_path:, dependency:, is_transitive:, credentials:)
        (command, fingerprint) = get_nuget_updater_tool_command(job_path: job_path, repo_root: repo_root,
                                                                proj_path: proj_path, dependency: dependency,
                                                                is_transitive: is_transitive,
                                                                result_output_path: update_result_file_path)

        puts "running NuGet updater:\n" + command

        NuGetConfigCredentialHelpers.patch_nuget_config_for_action(credentials) do
          output = SharedHelpers.run_shell_command(command,
                                                   allow_unsafe_shell_command: true,
                                                   fingerprint: fingerprint)
          puts output

          result_contents = File.read(update_result_file_path)
          Dependabot.logger.info("update result: #{result_contents}")
          result_json = T.let(JSON.parse(result_contents), T::Hash[String, T.untyped])
          ensure_no_errors(result_json)
        end
      end

      sig { void }
      def self.install_dotnet_sdks
        return unless Dependabot::Experiments.enabled?(:nuget_install_dotnet_sdks)

        # environment variables are required and the following will generate an actionable error message if they're not
        _dependabot_job_path = ENV.fetch("DEPENDABOT_JOB_PATH")
        _dependabot_repo_contents_path = ENV.fetch("DEPENDABOT_REPO_CONTENTS_PATH")
        _dotnet_install_script_path = ENV.fetch("DOTNET_INSTALL_SCRIPT_PATH")
        _dotnet_install_dir = ENV.fetch("DOTNET_INSTALL_DIR")

        # this environment variable is directly used
        dependabot_home = ENV.fetch("DEPENDABOT_HOME")

        command = [
          "pwsh",
          "#{dependabot_home}/dependabot-updater/bin/install-sdks.ps1"
        ].join(" ")
        output = SharedHelpers.run_shell_command(command)
        puts output
      end

      sig { params(json: T::Hash[String, T.untyped]).void }
      def self.ensure_no_errors(json)
        error_type = T.let(json.fetch("ErrorType", nil), T.nilable(String))
        error_details = json.fetch("ErrorDetails", nil)
        case error_type
        when "None", nil
          # no issue
        when "AuthenticationFailure"
          raise PrivateSourceAuthenticationFailure, T.let(error_details, T.nilable(String))
        when "MissingFile"
          raise DependencyFileNotFound, T.let(error_details, T.nilable(String))
        when "UpdateNotPossible"
          raise UpdateNotPossible, T.let(error_details, T::Array[String])
        when "Unknown"
          raise DependabotError, T.let(error_details, String)
        else
          raise "Unexpected error type from native tool: #{error_type}: #{error_details}"
        end
      end
    end
  end
end
