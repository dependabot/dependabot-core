# frozen_string_literal: true

require "json"
require "dependabot/file_fetchers/base"
require "dependabot/file_parsers/java_script/npm_and_yarn"

module Dependabot
  module FileFetchers
    module JavaScript
      class NpmAndYarn < Dependabot::FileFetchers::Base
        require_relative "npm_and_yarn/path_dependency_builder"

        def self.required_files_in?(filenames)
          filenames.include?("package.json")
        end

        def self.required_files_message
          "Repo must contain a package.json."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << package_json
          fetched_files << npmrc if npmrc
          fetched_files << package_lock if package_lock && !ignore_package_lock?
          fetched_files << yarn_lock if yarn_lock
          fetched_files += workspace_package_jsons
          fetched_files += path_dependencies

          fetched_files
        end

        def package_json
          @package_json ||= fetch_file_from_host("package.json")
        end

        def package_lock
          @package_lock ||= fetch_file_if_present("package-lock.json")
        end

        def yarn_lock
          @yarn_lock ||= fetch_file_if_present("yarn.lock")
        end

        def npmrc
          @npmrc ||= fetch_file_if_present(".npmrc")
        end

        def path_dependencies
          package_json_files = []
          unfetchable_deps = []

          types = FileParsers::JavaScript::NpmAndYarn::DEPENDENCY_TYPES

          package_json_path_deps =
            parsed_package_json.values_at(*types).compact.flat_map(&:to_a).
            select { |_, v| v.start_with?("file:") }

          package_lock_path_deps =
            parsed_package_lock.fetch("dependencies", []).to_a.
            select { |_, v| v.fetch("version", "").start_with?("file:") }.
            map { |k, v| [k, v.fetch("version")] }

          path_deps = (package_json_path_deps + package_lock_path_deps).uniq

          path_deps.map do |name, path|
            path = path.sub(/^file:/, "")
            file = File.join(path, "package.json")

            begin
              package_json_files <<
                fetch_file_from_host(file, type: "path_dependency")
            rescue Dependabot::DependencyFileNotFound
              unfetchable_deps << [name, path]
            end
          end

          package_json_files += build_unfetchable_deps(unfetchable_deps)

          package_json_files
        end

        def workspace_package_jsons
          return [] unless parsed_package_json["workspaces"]
          package_json_files = []
          unfetchable_deps = []

          workspace_paths(parsed_package_json["workspaces"]).each do |workspace|
            file = File.join(workspace, "package.json")

            begin
              package_json_files << fetch_file_from_host(file)
            rescue Dependabot::DependencyFileNotFound
              unfetchable_deps << file
            end
          end

          if unfetchable_deps.any?
            raise Dependabot::PathDependenciesNotReachable, unfetchable_deps
          end

          package_json_files
        end

        def workspace_paths(workspace_object)
          paths_array =
            if workspace_object.is_a?(Hash) then workspace_object["packages"]
            elsif workspace_object.is_a?(Array) then workspace_object
            else raise "Unexpected workspace object"
            end

          paths_array.flat_map do |path|
            if path.end_with?("*") then expand_workspaces(path)
            else path
            end
          end
        end

        def expand_workspaces(path)
          dir = directory.gsub(%r{(^/|/$)}, "")
          repo_contents(dir: path.gsub(/\*$/, "")).
            select { |file| file.type == "dir" }.
            map { |f| f.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "") }
        end

        def parsed_package_json
          JSON.parse(package_json.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, package_json.path
        end

        def parsed_package_lock
          return {} unless package_lock
          JSON.parse(package_lock.content)
        rescue JSON::ParserError
          {}
        end

        def ignore_package_lock?
          return false unless npmrc
          npmrc.content.match?(/^package-lock\s*=\s*false/)
        end

        def build_unfetchable_deps(unfetchable_deps)
          return [] unless package_lock || yarn_lock

          unfetchable_deps.map do |name, path|
            PathDependencyBuilder.new(
              dependency_name: name,
              path: path,
              directory: directory,
              package_lock: package_lock,
              yarn_lock: yarn_lock
            ).dependency_file
          end
        end
      end
    end
  end
end
