# frozen_string_literal: true

require "json"
require "dependabot/logger"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser"

module Dependabot
  module NpmAndYarn
    # rubocop:disable Metrics/ClassLength
    class FileFetcher < Dependabot::FileFetchers::Base
      require_relative "file_fetcher/path_dependency_builder"

      # Npm always prefixes file paths in the lockfile "version" with "file:"
      # even when a naked path is used (e.g. "../dep")
      NPM_PATH_DEPENDENCY_STARTS = %w(file:).freeze
      # "link:" is only supported by Yarn but is interchangeable with "file:"
      # when it specifies a path. Only include Yarn "link:"'s that start with a
      # path and ignore symlinked package names that have been registered with
      # "yarn link", e.g. "link:react"
      PATH_DEPENDENCY_STARTS = %w(file: link:. link:/ link:~/ / ./ ../ ~/).freeze
      PATH_DEPENDENCY_CLEAN_REGEX = /^file:|^link:/

      def self.required_files_in?(filenames)
        filenames.include?("package.json")
      end

      def self.required_files_message
        "Repo must contain a package.json."
      end

      # Overridden to pull any yarn data or plugins which may be stored with Git LFS.
      def clone_repo_contents
        return @git_lfs_cloned_repo_contents_path if defined?(@git_lfs_cloned_repo_contents_path)

        @git_lfs_cloned_repo_contents_path = super
        begin
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(@git_lfs_cloned_repo_contents_path) do
              cache_dir = Helpers.fetch_yarnrc_yml_value("cacheFolder", "./yarn/cache")
              SharedHelpers.run_shell_command("git lfs pull --include .yarn,#{cache_dir}")
            end
            @git_lfs_cloned_repo_contents_path
          end
        rescue StandardError
          @git_lfs_cloned_repo_contents_path
        end
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << package_json
        fetched_files << package_lock if package_lock && !ignore_package_lock?
        fetched_files << yarn_lock if yarn_lock
        fetched_files << shrinkwrap if shrinkwrap
        fetched_files << lerna_json if lerna_json
        fetched_files << npmrc if npmrc
        fetched_files << yarnrc if yarnrc
        fetched_files << yarnrc_yml if yarnrc_yml
        fetched_files += workspace_package_jsons
        fetched_files += lerna_packages
        fetched_files += path_dependencies(fetched_files)
        instrument_package_manager_version

        fetched_files << inferred_npmrc if inferred_npmrc

        fetched_files.uniq
      end

      # If every entry in the lockfile uses the same registry, we can infer
      # that there is a global .npmrc file, so add it here as if it were in the repo.
      def inferred_npmrc
        return @inferred_npmrc if defined?(@inferred_npmrc)
        return @inferred_npmrc = nil unless npmrc.nil? && package_lock

        known_registries = []
        JSON.parse(package_lock.content).fetch("dependencies", {}).each do |_name, details|
          resolved = details.fetch("resolved", "https://registry.npmjs.org")
          begin
            uri = URI.parse(resolved)
          rescue URI::InvalidURIError
            # Ignoring non-URIs since they're not registries.
            # This can happen if resolved is false, for instance.
            next
          end
          # Check for scheme since path dependencies will not have one
          known_registries << "#{uri.scheme}://#{uri.host}" if uri.scheme && uri.host
        end

        if known_registries.uniq.length == 1 && known_registries.first != "https://registry.npmjs.org"
          Dependabot.logger.info("Inferred global NPM registry is: #{known_registries.first}")
          return @inferred_npmrc = Dependabot::DependencyFile.new(
            name: ".npmrc",
            content: "registry=#{known_registries.first}"
          )
        end

        @inferred_npmrc = nil
      end

      def instrument_package_manager_version
        package_managers = {}

        package_managers["npm"] = Helpers.npm_version_numeric(package_lock.content) if package_lock
        package_managers["yarn"] = yarn_version if yarn_version
        package_managers["shrinkwrap"] = 1 if shrinkwrap

        Dependabot.instrument(
          Notifications::FILE_PARSER_PACKAGE_MANAGER_VERSION_PARSED,
          ecosystem: "npm",
          package_managers: package_managers
        )
      end

      def yarn_version
        return @yarn_version if defined?(@yarn_version)

        package = JSON.parse(package_json.content)
        if (package_manager = package.fetch("packageManager", nil))
          get_yarn_version_from_package_json(package_manager)
        elsif yarn_lock
          1
        end
      end

      def get_yarn_version_from_package_json(package_manager)
        version_match = package_manager.match(/yarn@(?<version>\d+.\d+.\d+)/)
        version_match&.named_captures&.fetch("version", nil)
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

      def shrinkwrap
        @shrinkwrap ||= fetch_file_if_present("npm-shrinkwrap.json")
      end

      def npmrc
        @npmrc ||= fetch_file_if_present(".npmrc")&.
                   tap { |f| f.support_file = true }

        return @npmrc if @npmrc || directory == "/"

        # Loop through parent directories looking for an npmrc
        (1..directory.split("/").count).each do |i|
          @npmrc = fetch_file_from_host(("../" * i) + ".npmrc")&.
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
          @yarnrc = fetch_file_from_host(("../" * i) + ".yarnrc")&.
                   tap { |f| f.support_file = true }
          break if @yarnrc
        rescue Dependabot::DependencyFileNotFound
          # Ignore errors (.yarnrc may not be present)
          nil
        end

        @yarnrc
      end

      def yarnrc_yml
        @yarnrc_yml ||= fetch_file_if_present(".yarnrc.yml")&.
                       tap { |f| f.support_file = true }
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

      # rubocop:disable Metrics/PerceivedComplexity
      def path_dependencies(fetched_files)
        package_json_files = []
        unfetchable_deps = []

        path_dependency_details(fetched_files).each do |name, path|
          # This happens with relative paths in the package-lock. Skipping it since it results
          # in /package.json which is outside of the project directory.
          next if path == "file:"

          path = path.gsub(PATH_DEPENDENCY_CLEAN_REGEX, "")
          raise PathDependenciesNotReachable, "#{name} at #{path}" if path.start_with?("/")

          filename = path
          # NPM/Yarn support loading path dependencies from tarballs:
          # https://docs.npmjs.com/cli/pack.html
          filename = File.join(filename, "package.json") unless filename.end_with?(".tgz", ".tar", ".tar.gz")
          cleaned_name = Pathname.new(filename).cleanpath.to_path
          next if fetched_files.map(&:name).include?(cleaned_name)

          begin
            file = fetch_file_from_host(filename, fetch_submodules: true)
            package_json_files << file
          rescue Dependabot::DependencyFileNotFound
            # Unfetchable tarballs should not be re-fetched as a package
            unfetchable_deps << [name, path] unless path.end_with?(".tgz", ".tar", ".tar.gz")
          end
        end

        package_json_files += build_unfetchable_deps(unfetchable_deps)

        if package_json_files.any?
          package_json_files +=
            path_dependencies(fetched_files + package_json_files)
        end

        package_json_files.tap { |fs| fs.each { |f| f.support_file = true } }
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def path_dependency_details(fetched_files)
        package_json_path_deps = []

        fetched_files.each do |file|
          package_json_path_deps +=
            path_dependency_details_from_manifest(file)
        end

        package_lock_path_deps = path_dependency_details_from_npm_lockfile(
          parsed_package_lock
        )
        shrinkwrap_path_deps = path_dependency_details_from_npm_lockfile(
          parsed_shrinkwrap
        )

        [
          *package_json_path_deps,
          *package_lock_path_deps,
          *shrinkwrap_path_deps
        ].uniq
      end

      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      def path_dependency_details_from_manifest(file)
        return [] unless file.name.end_with?("package.json")

        current_dir = file.name.rpartition("/").first
        current_dir = nil if current_dir == ""

        dep_types = NpmAndYarn::FileParser::DEPENDENCY_TYPES
        parsed_manifest = JSON.parse(file.content)
        dependency_objects = parsed_manifest.values_at(*dep_types).compact
        # Fetch yarn "file:" path "resolutions" so the lockfile can be resolved
        resolution_objects = parsed_manifest.values_at("resolutions").compact
        manifest_objects = dependency_objects + resolution_objects

        raise Dependabot::DependencyFileNotParseable, file.path unless manifest_objects.all?(Hash)

        resolution_deps = resolution_objects.flat_map(&:to_a).
                          map do |path, value|
                            convert_dependency_path_to_name(path, value)
                          end

        path_starts = PATH_DEPENDENCY_STARTS
        (dependency_objects.flat_map(&:to_a) + resolution_deps).
          select { |_, v| v.is_a?(String) && v.start_with?(*path_starts) }.
          map do |name, path|
            path = path.gsub(PATH_DEPENDENCY_CLEAN_REGEX, "")
            raise PathDependenciesNotReachable, "#{name} at #{path}" if path.start_with?("/")

            path = File.join(current_dir, path) unless current_dir.nil?
            [name, Pathname.new(path).cleanpath.to_path]
          end
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, file.path
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/PerceivedComplexity

      def path_dependency_details_from_npm_lockfile(parsed_lockfile)
        path_starts = NPM_PATH_DEPENDENCY_STARTS
        parsed_lockfile.fetch("dependencies", []).to_a.
          select { |_, v| v.is_a?(Hash) }.
          select { |_, v| v.fetch("version", "").start_with?(*path_starts) }.
          map { |k, v| [k, v.fetch("version")] }
      end

      # Re-write the glob name to the targeted dependency name (which is used
      # in the lockfile), for example "parent-package/**/sub-dep/target-dep" >
      # "target-dep"
      def convert_dependency_path_to_name(path, value)
        # Picking the last two parts that might include a scope
        parts = path.split("/").last(2)
        parts.shift if parts.count == 2 && !parts.first.start_with?("@")
        [parts.join("/"), value]
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
              find_directories(File.join(path, "*")).flat_map do |nested_path|
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
          else
            [] # Invalid lerna.json, which must not be in use
          end

        paths_array.flat_map { |path| recursive_find_directories(path) }
      end

      # Only expands globs one level deep, so path/**/* gets expanded to path/
      def find_directories(glob)
        return [glob] unless glob.include?("*") || yarn_ignored_glob(glob)

        unglobbed_path =
          glob.gsub(%r{^\./}, "").gsub(/!\(.*?\)/, "*").
          split("*").
          first&.gsub(%r{(?<=/)[^/]*$}, "") || "."

        dir = directory.gsub(%r{(^/|/$)}, "")

        paths =
          repo_contents(dir: unglobbed_path, raise_errors: false).
          select { |file| file.type == "dir" }.
          map { |f| f.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "") }

        matching_paths(glob, paths)
      end

      def matching_paths(glob, paths)
        ignored_glob = yarn_ignored_glob(glob)
        glob = glob.gsub(%r{^\./}, "").gsub(/!\(.*?\)/, "*")

        results = paths.select { |filename| File.fnmatch?(glob, filename) }
        return results unless ignored_glob

        results.reject { |filename| File.fnmatch?(ignored_glob, filename) }
      end

      def recursive_find_directories(glob, prefix = "")
        return [prefix + glob] unless glob.include?("*") || yarn_ignored_glob(glob)

        glob = glob.gsub(%r{^\./}, "")
        glob_parts = glob.split("/")

        paths = find_directories(prefix + glob_parts.first)
        next_parts = glob_parts.drop(1)
        return paths if next_parts.empty?

        paths = paths.flat_map do |expanded_path|
          recursive_find_directories(next_parts.join("/"), "#{expanded_path}/")
        end

        matching_paths(prefix + glob, paths)
      end

      # The packages/!(not-this-package) syntax is unique to Yarn
      def yarn_ignored_glob(glob)
        glob.match?(/!\(.*?\)/) && glob.gsub(/(!\((.*?)\))/, '\2')
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
    # rubocop:enable Metrics/ClassLength
  end
end

Dependabot::FileFetchers.
  register("npm_and_yarn", Dependabot::NpmAndYarn::FileFetcher)
