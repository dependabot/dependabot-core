# typed: true
# frozen_string_literal: true

require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/dependency"
require "json"
require "uri"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      class DependencyParser
        def initialize(dependency_files:, repo_contents_path:, credentials:)
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        def parse
          SharedHelpers.in_a_temporary_repo_directory(dependency_files.first.directory, repo_contents_path) do
            write_temporary_dependency_files

            SharedHelpers.with_git_configured(credentials: credentials) do
              subdependencies(formatted_deps)
            end
          end
        end

        private

        def write_temporary_dependency_files
          dependency_files.each do |file|
            File.write(file.name, file.content)
          end
        end

        def formatted_deps
          deps = SharedHelpers.run_shell_command(
            "swift package show-dependencies --format json",
            stderr_to_stdout: false
          )

          JSON.parse(deps)
        end

        def subdependencies(data, level: 0)
          data["dependencies"].flat_map { |root| all_dependencies(root, level: level) }
        end

        def all_dependencies(data, level: 0)
          identity = data["identity"]
          url = SharedHelpers.scp_to_standard(data["url"])
          name = normalize(url)
          version = data["version"]

          source = { type: "git", url: url, ref: version, branch: nil }
          metadata = { identity: identity }
          args = { name: name, version: version, package_manager: "swift", requirements: [], metadata: metadata }

          if level.zero?
            args[:requirements] << { requirement: nil, groups: ["dependencies"], file: nil, source: source }
          else
            args[:subdependency_metadata] = [{ source: source }]
          end

          dep = Dependency.new(**args) if data["version"] != "unspecified"

          [dep, *subdependencies(data, level: level + 1)].compact
        end

        def normalize(source)
          uri = URI.parse(source.downcase)

          "#{uri.host}#{uri.path}".delete_prefix("www.").delete_suffix(".git")
        end

        attr_reader :dependency_files
        attr_reader :repo_contents_path
        attr_reader :credentials
      end
    end
  end
end
