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

          def parsed_package_lock
            return {} unless package_lock
            JSON.parse(package_lock.content)
          rescue JSON::ParserError
            {}
          end

          def build_path_dep_content(dependency_name)
            package_lock_details =
              parsed_package_lock.fetch("dependencies", []).to_a.
              select { |_, v| v.fetch("version", "").start_with?("file:") }.
              find { |n, _| n == dependency_name }&.
              last

            # TODO: Check yarn.lock for details instead of raising
            unless package_lock_details
              raise Dependabot::PathDependenciesNotReachable, [dependency_name]
            end

            {
              name: dependency_name,
              version: "0.0.1",
              dependencies: package_lock_details["requires"]
            }.compact.to_json
          end
        end
      end
    end
  end
end
