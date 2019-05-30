# frozen_string_literal: true

require "json"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/npm_and_yarn/file_parser"

module Dependabot
  module NpmAndYarn
    class FileFetcher < Dependabot::FileFetchers::Base
      require_relative "file_fetcher/path_dependency_builder"

      def self.required_files_in?(filenames)
        filenames.include?("package.json")
      end

      def self.required_files_message
        "Repo must contain a package.json."
      end

      private

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def fetch_files
        fetched_files = []
        fetched_files << package_json
        fetched_files << package_lock if package_lock && !ignore_package_lock?
        fetched_files << yarn_lock if yarn_lock
        fetched_files << shrinkwrap if shrinkwrap
        fetched_files << lerna_json if lerna_json
        fetched_files << npmrc if npmrc
        fetched_files << yarnrc if yarnrc
        fetched_files += workspace_package_jsons
        fetched_files += lerna_packages
        fetched_files += path_dependencies(fetched_files)

        fetched_files.uniq
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      def package_json
        @package_json ||= fetch_file_from_host("package.json")
      end

      def package_lock
        @package_lock ||= fetch_file_if_present("package-lock.json")
      end

      def yarn_lock
        @yarn_lock ||= fetch_file_if_present("yarn.lock")
      end

      def shrinkwrap
        @shrinkwrap ||= fetch_file_if_present("npm-shrinkwrap.json")
      end

      def npmrc
        @npmrc ||= fetch_file_if_present(".npmrc")&.
                   tap { |f| f.support_file = true }

        return @npmrc if @npmrc || directory == "/"

        # Loop through parent directories looking for an npmrc
        (1..directory.split("/").count).each do |i|
          @npmrc = fetch_file_from_host("../" * i + ".npmrc")&.
                   tap { |f| f.support_file = true }
          break if @npmrc
        rescue Dependabot::DependencyFileNotFound
          # Ignore errors (.npmrc may not be present)
          nil
        end

        @npmrc
      end

      def yarnrc
        @yarnrc ||= fetch_file_if_present(".yarnrc")&.
                   tap { |f| f.support_file = true }

        return @yarnrc if @yarnrc || directory == "/"

        # Loop through parent directories looking for an yarnrc
        (1..directory.split("/").count).each do |i|
          @yarnrc = fetch_file_from_host("../" * i + ".yarnrc")&.
                   tap { |f| f.support_file = true }
          break if @yarnrc
        rescue Dependabot::DependencyFileNotFound
          # Ignore errors (.yarnrc may not be present)
          nil
        end

        @yarnrc
      end

      def lerna_json
        @lerna_json ||= fetch_file_if_present("lerna.json")&.
                        tap { |f| f.support_file = true }
      end

      def workspace_package_jsons
        @workspace_package_jsons ||= fetch_workspace_package_jsons
      end

      def lerna_packages
        @lerna_packages ||= fetch_lerna_packages
      end

      def path_dependencies(fetched_files)
        package_json_files = []
        unfetchable_deps = []

        path_dependency_details(fetched_files).each do |name, path|
          path = path.sub(/^file:/, "").sub(/^link:/, "")
          filename = File.join(path, "package.json")
          cleaned_name = Pathname.new(filename).cleanpath.to_path
          next if fetched_files.map(&:name).include?(cleaned_name)

          begin
            file = fetch_file_from_host(filename, fetch_submodules: true)
            package_json_files << file
          rescue Dependabot::DependencyFileNotFound
            unfetchable_deps << [name, path]
          end
        end

        package_json_files += build_unfetchable_deps(unfetchable_deps)

        if package_json_files.any?
          package_json_files +=
            path_dependencies(fetched_files + package_json_files)
        end

        package_json_files.tap { |fs| fs.each { |f| f.support_file = true } }
      end

      def path_dependency_details(fetched_files)
        package_json_path_deps = []

        fetched_files.each do |file|
          package_json_path_deps +=
            path_dependency_details_from_manifest(file)
        end

        path_starts = %w(file: link:.)

        package_lock_path_deps =
          parsed_package_lock.fetch("dependencies", []).to_a.
          select { |_, v| v.fetch("version", "").start_with?(*path_starts) }.
          map { |k, v| [k, v.fetch("version")] }

        shrinkwrap_path_deps =
          parsed_shrinkwrap.fetch("dependencies", []).to_a.
          select { |_, v| v.fetch("version", "").start_with?(*path_starts) }.
          map { |k, v| [k, v.fetch("version")] }

        [
          *package_json_path_deps,
          *package_lock_path_deps,
          *shrinkwrap_path_deps
        ].uniq
      end

      def path_dependency_details_from_manifest(file)
        return [] unless file.name.end_with?("package.json")

        current_dir = file.name.rpartition("/").first
        current_dir = nil if current_dir == ""
        path_dep_starts = %w(file: / ./ ../ ~/ link:.)

        dependency_objects =
          JSON.parse(file.content).
          values_at(*NpmAndYarn::FileParser::DEPENDENCY_TYPES).compact

        unless dependency_objects.all? { |o| o.is_a?(Hash) }
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        dependency_objects.flat_map(&:to_a).
          select { |_, v| v.is_a?(String) && v.start_with?(*path_dep_starts) }.
          map do |name, path|
            path = path.sub(/^file:/, "").sub(/^link:/, "")
            path = File.join(current_dir, path) unless current_dir.nil?
            [name, Pathname.new(path).cleanpath.to_path]
          end
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      def fetch_workspace_package_jsons
        return [] unless parsed_package_json["workspaces"]

        package_json_files = []

        workspace_paths(parsed_package_json["workspaces"]).each do |workspace|
          file = File.join(workspace, "package.json")

          begin
            package_json_files << fetch_file_from_host(file)
          rescue Dependabot::DependencyFileNotFound
            nil
          end
        end

        package_json_files
      end

      def fetch_lerna_packages
        return [] unless parsed_lerna_json["packages"]

        dependency_files = []

        workspace_paths(parsed_lerna_json["packages"]).each do |workspace|
          dependency_files += fetch_lerna_packages_from_path(workspace)
        end

        dependency_files
      end

      def fetch_lerna_packages_from_path(path, nested = false)
        dependency_files = []

        package_json_path = File.join(path, "package.json")

        begin
          dependency_files << fetch_file_from_host(package_json_path)
          dependency_files += [
            fetch_file_if_present(File.join(path, "package-lock.json")),
            fetch_file_if_present(File.join(path, "yarn.lock")),
            fetch_file_if_present(File.join(path, "npm-shrinkwrap.json"))
          ].compact
        rescue Dependabot::DependencyFileNotFound
          matches_double_glob =
            parsed_lerna_json["packages"].any? do |globbed_path|
              next false unless globbed_path.include?("**")

              File.fnmatch?(globbed_path, path)
            end

          if matches_double_glob && !nested
            dependency_files +=
              expanded_paths(File.join(path, "*")).flat_map do |nested_path|
                fetch_lerna_packages_from_path(nested_path, true)
              end
          end
        end

        dependency_files
      end

      def workspace_paths(workspace_object)
        paths_array =
          if workspace_object.is_a?(Hash)
            workspace_object.values_at("packages", "nohoist").flatten.compact
          elsif workspace_object.is_a?(Array) then workspace_object
          else raise "Unexpected workspace object"
          end

        paths_array.flat_map do |path|
          # The packages/!(not-this-package) syntax is unique to Yarn
          if path.include?("*") || path.include?("!(")
            expanded_paths(path)
          else path
          end
        end
      end

      def expanded_paths(path)
        ignored_paths = path.scan(/!\((.*?)\)/).flatten

        dir = directory.gsub(%r{(^/|/$)}, "")
        path = path.gsub(%r{^\./}, "").gsub(/!\(.*?\)/, "*")
        unglobbed_path = path.split("*").first&.gsub(%r{(?<=/)[^/]*$}, "") ||
                         "."

        repo_contents(dir: unglobbed_path, raise_errors: false).
          select { |file| file.type == "dir" }.
          map { |f| f.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "") }.
          select { |filename| File.fnmatch?(path, filename) }.
          reject { |fn| ignored_paths.any? { |p| fn.include?(p) } }
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

      def parsed_shrinkwrap
        return {} unless shrinkwrap

        JSON.parse(shrinkwrap.content)
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

      def parsed_lerna_json
        return {} unless lerna_json

        JSON.parse(lerna_json.content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, lerna_json.path
      end
    end
  end
end

Dependabot::FileFetchers.
  register("npm_and_yarn", Dependabot::NpmAndYarn::FileFetcher)
