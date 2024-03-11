# typed: strict
# frozen_string_literal: true

require "dependabot/devcontainers/requirement"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/dependency"
require "json"
require "sorbet-runtime"
require "uri"

module Dependabot
  module Devcontainers
    class FileParser < Dependabot::FileParsers::Base
      class ImageDependencyParser
        extend T::Sig

        sig do
          params(
            config_dependency_file: Dependabot::DependencyFile,
            repo_contents_path: T.nilable(String),
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(config_dependency_file:, repo_contents_path:, credentials:)
          @config_dependency_file = config_dependency_file
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def parse
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            SharedHelpers.with_git_configured(credentials: credentials) do
              parse_cli_json(evaluate_with_cli)
            end
          end
        end

        private

        sig { returns(String) }
        def base_dir
          File.dirname(config_dependency_file.path)
        end

        sig { returns(String) }
        def config_name
          File.basename(config_dependency_file.path)
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def evaluate_with_cli
          raise "config_name must be a string" unless config_name.is_a?(String) && !config_name.empty?

          cmd = "devcontainer outdated --workspace-folder . --only-images --config #{config_name} --output-format json"
          Dependabot.logger.info("Running command: #{cmd}")

          json = SharedHelpers.run_shell_command(
            cmd,
            stderr_to_stdout: false
          )

          JSON.parse(json)
        end

        sig { params(json: T::Hash[String, T.untyped]).returns(T::Array[Dependabot::Dependency]) }
        def parse_cli_json(json)
          dependencies = []

          images = json["images"]
          images.each do |image, image_object|
            dep = Dependency.new(
              name: image_object["name"],
              version: image_object["currentImageValue"],
              package_manager: "devcontainers",
              requirements: [
                {
                  requirement: image_object["newImageValue"],
                  # current_image: image_object["currentImageValue"],
                  # new_image: image_object["newImageValue"],
                  file: image["path"],
                  groups: ["image"],
                  source: nil
                }
              ]
            )

            dependencies << dep
          end
          dependencies
        end

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :config_dependency_file

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
      end
    end
  end
end
