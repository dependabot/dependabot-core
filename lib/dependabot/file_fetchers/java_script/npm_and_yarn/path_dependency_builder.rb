# frozen_string_literal: true

require "json"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/file_fetchers/java_script/npm_and_yarn"

module Dependabot
  module FileFetchers
    module JavaScript
      class NpmAndYarn
        class PathDependencyBuilder
          def initialize(dependency_name:, path:, directory:, package_lock:,
                         yarn_lock:)
            @dependency_name = dependency_name
            @path = path
            @directory = directory
            @package_lock = package_lock
            @yarn_lock = yarn_lock
          end

          def dependency_file
            filename = File.join(path, "package.json")

            DependencyFile.new(
              name: Pathname.new(filename).cleanpath.to_path,
              content: build_path_dep_content(dependency_name),
              directory: directory,
              type: "path_dependency"
            )
          end

          private

          attr_reader :dependency_name, :path, :package_lock, :yarn_lock,
                      :directory

          def details_from_yarn_lock
            parsed_yarn_lock.to_a.
              find do |n, _|
                next false unless n.split(/(?<=\w)\@/).first == dependency_name
                n.split(/(?<=\w)\@/).last.start_with?("file:")
              end&.last
          end

          def details_from_npm_lock
            parsed_package_lock.fetch("dependencies", []).to_a.
              select { |_, v| v.fetch("version", "").start_with?("file:") }.
              find { |n, _| n == dependency_name }&.
              last
          end

          def build_path_dep_content(dependency_name)
            unless details_from_yarn_lock || details_from_npm_lock
              raise Dependabot::PathDependenciesNotReachable, [dependency_name]
            end

            if details_from_yarn_lock
              {
                name: dependency_name,
                version: "0.0.1",
                dependencies: details_from_yarn_lock["dependencies"],
                optionalDependencies:
                  details_from_yarn_lock["optionalDependencies"]
              }.compact.to_json
            else
              {
                name: dependency_name,
                version: "0.0.1",
                dependencies: details_from_npm_lock["requires"]
              }.compact.to_json
            end
          end

          def parsed_package_lock
            return {} unless package_lock
            JSON.parse(package_lock.content)
          rescue JSON::ParserError
            {}
          end

          def parsed_yarn_lock
            return {} unless yarn_lock
            @parsed_yarn_lock ||=
              SharedHelpers.in_a_temporary_directory do
                File.write("yarn.lock", yarn_lock.content)

                SharedHelpers.run_helper_subprocess(
                  command: "node #{yarn_helper_path}",
                  function: "parseLockfile",
                  args: [Dir.pwd]
                )
              end
          end

          def yarn_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/yarn/bin/run.js")
          end
        end
      end
    end
  end
end
