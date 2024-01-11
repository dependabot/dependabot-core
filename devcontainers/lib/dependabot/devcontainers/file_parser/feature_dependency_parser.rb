# typed: true
# frozen_string_literal: true

require "dependabot/devcontainers/requirement"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/dependency"
require "json"
require "uri"

module Dependabot
  module Devcontainers
    class FileParser < Dependabot::FileParsers::Base
      class FeatureDependencyParser
        def initialize(config_dependency_file:, repo_contents_path:, credentials:)
          @config_dependency_file = config_dependency_file
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        def parse
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            SharedHelpers.with_git_configured(credentials: credentials) do
              parse_cli_json(evaluate_with_cli)
            end
          end
        end

        private

        def base_dir
          File.dirname(config_dependency_file.path)
        end

        def config_name
          File.basename(config_dependency_file.path)
        end

        def config_contents
          config_dependency_file.content
        end

        # https://github.com/devcontainers/cli/blob/9444540283b236298c28f397dea879e7ec222ca1/src/spec-node/devContainersSpecCLI.ts#L1072
        def evaluate_with_cli
          raise "config_name must be a string" unless config_name.is_a?(String) && !config_name.empty?

          cmd = "devcontainer outdated --workspace-folder . --config #{config_name} --output-format json"
          Dependabot.logger.info("Running command: #{cmd}")

          json = SharedHelpers.run_shell_command(
            cmd,
            stderr_to_stdout: false
          )

          JSON.parse(json)
        end

        def parse_cli_json(json)
          dependencies = []

          features = json["features"]
          features.each do |feature, versions_object|
            name, requirement = feature.split(":")
            current = versions_object["current"]
            wanted = versions_object["wanted"]
            latest = versions_object["latest"]
            wanted_major = versions_object["wantedMajor"]
            latest_major = versions_object["latestMajor"]

            dep = Dependency.new(
              name: name,
              version: current,
              package_manager: "devcontainers",
              requirements: [
                {
                  requirement: requirement,
                  file: config_dependency_file.name,
                  groups: ["feature"],
                  source: nil,
                  metadata: {
                    wanted: wanted,
                    latest: latest,
                    wanted_major: wanted_major,
                    latest_major: latest_major
                  }
                }
              ],
              metadata: {}
            )

            dependencies << dep
          end
          dependencies
        end

        attr_reader :config_dependency_file, :repo_contents_path, :credentials
      end
    end
  end
end
