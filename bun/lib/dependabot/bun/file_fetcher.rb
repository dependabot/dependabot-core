# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/experiments"
require "dependabot/logger"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/bun/helpers"
require "dependabot/bun/package_manager"
require "dependabot/bun/file_parser"
require "dependabot/bun/file_parser/lockfile_parser"

module Dependabot
  module Bun
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      require_relative "file_fetcher/path_dependency_builder"

      # Npm always prefixes file paths in the lockfile "version" with "file:"
      # even when a naked path is used (e.g. "../dep")
      NPM_PATH_DEPENDENCY_STARTS = T.let(%w(file:).freeze, [String])
      # "link:" is only supported by Yarn but is interchangeable with "file:"
      # when it specifies a path. Only include Yarn "link:"'s that start with a
      # path and ignore symlinked package names that have been registered with
      # "yarn link", e.g. "link:react"
      PATH_DEPENDENCY_STARTS = T.let(%w(file: link:. link:/ link:~/ / ./ ../ ~/).freeze,
                                     [String, String, String, String, String, String, String, String])
      PATH_DEPENDENCY_CLEAN_REGEX = /^file:|^link:/
      DEFAULT_NPM_REGISTRY = "https://registry.npmjs.org"

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("package.json")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a package.json."
      end

      # Overridden to pull any necessary data stored with Git LFS.
      sig { override.returns(String) }
      def clone_repo_contents
        return @git_lfs_cloned_repo_contents_path unless @git_lfs_cloned_repo_contents_path.nil?

        @git_lfs_cloned_repo_contents_path ||= T.let(super, T.nilable(String))
        begin
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(@git_lfs_cloned_repo_contents_path) do
              SharedHelpers.run_shell_command("git lfs pull --include .yarn")
            end
            @git_lfs_cloned_repo_contents_path
          end
        rescue StandardError
          @git_lfs_cloned_repo_contents_path
        end
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        package_managers = {}

        package_managers["bun"] = bun_version if bun_version
        package_managers["unknown"] = 1 if package_managers.empty?

        {
          package_managers: package_managers
        }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = T.let([], T::Array[DependencyFile])
        fetched_files << package_json
        fetched_files << T.must(npmrc) if npmrc
        fetched_files += bun_files if bun_version
        fetched_files += workspace_package_jsons
        fetched_files += path_dependencies(fetched_files)

        fetched_files.uniq
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def bun_files
        fetched_bun_files = []
        fetched_bun_files << bun_lock if bun_lock
        fetched_bun_files
      end

      # If every entry in the lockfile uses the same registry, we can infer
      # that there is a global .npmrc file, so add it here as if it were in the repo.

      sig { returns(T.nilable(T.any(Integer, String))) }
      def bun_version
        return @bun_version = nil unless allow_beta_ecosystems?

        @bun_version ||= T.let(
          package_manager_helper.setup(BunPackageManager::NAME),
          T.nilable(T.any(Integer, String))
        )
      end

      sig { returns(PackageManagerHelper) }
      def package_manager_helper
        @package_manager_helper ||= T.let(
          PackageManagerHelper.new(
            parsed_package_json,
            lockfiles,
            registry_config_files,
            credentials
          ), T.nilable(PackageManagerHelper)
        )
      end

      sig { returns(T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)]) }
      def lockfiles
        {
          bun: bun_lock
        }
      end

      # Returns the .npmrc, and .yarnrc files for the repository.
      # @return [Hash{Symbol => Dependabot::DependencyFile}]
      sig { returns(T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)]) }
      def registry_config_files
        {
          npmrc: npmrc
        }
      end

      sig { returns(DependencyFile) }
      def package_json
        @package_json ||= T.let(fetch_file_from_host(MANIFEST_FILENAME), T.nilable(DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def bun_lock
        return @bun_lock if defined?(@bun_lock)

        @bun_lock ||= T.let(fetch_file_if_present(BunPackageManager::LOCKFILE_NAME), T.nilable(DependencyFile))

        return @bun_lock if @bun_lock || directory == "/"

        @bun_lock = fetch_file_from_parent_directories(BunPackageManager::LOCKFILE_NAME)
      end

      sig { returns(T.nilable(DependencyFile)) }
      def npmrc
        return @npmrc if defined?(@npmrc)

        @npmrc ||= T.let(fetch_support_file(BunPackageManager::RC_FILENAME), T.nilable(DependencyFile))

        return @npmrc if @npmrc || directory == "/"

        @npmrc = fetch_file_from_parent_directories(BunPackageManager::RC_FILENAME)
      end

      sig { returns(T::Array[DependencyFile]) }
      def workspace_package_jsons
        @workspace_package_jsons ||= T.let(fetch_workspace_package_jsons, T.nilable(T::Array[DependencyFile]))
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(fetched_files: T::Array[DependencyFile]).returns(T::Array[DependencyFile]) }
      def path_dependencies(fetched_files)
        package_json_files = T.let([], T::Array[DependencyFile])
        unfetchable_deps = T.let([], T::Array[[String, String]])

        path_dependency_details(fetched_files).each do |name, path|
          # This happens with relative paths in the package-lock. Skipping it since it results
          # in /package.json which is outside of the project directory.
          next if path == "file:"

          path = path.gsub(PATH_DEPENDENCY_CLEAN_REGEX, "")
          raise PathDependenciesNotReachable, "#{name} at #{path}" if path.start_with?("/")

          filename = path
          # NPM/Yarn support loading path dependencies from tarballs:
          # https://docs.npmjs.com/cli/pack.html
          filename = File.join(filename, MANIFEST_FILENAME) unless filename.end_with?(".tgz", ".tar", ".tar.gz")
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

        if package_json_files.any?
          package_json_files +=
            path_dependencies(fetched_files + package_json_files)
        end

        package_json_files.tap { |fs| fs.each { |f| f.support_file = true } }
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(fetched_files: T::Array[DependencyFile]).returns(T::Array[[String, String]]) }
      def path_dependency_details(fetched_files)
        package_json_path_deps = T.let([], T::Array[[String, String]])

        fetched_files.each do |file|
          package_json_path_deps +=
            path_dependency_details_from_manifest(file)
        end

        [*package_json_path_deps].uniq
      end

      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      sig { params(file: DependencyFile).returns(T::Array[[String, String]]) }
      def path_dependency_details_from_manifest(file)
        return [] unless file.name.end_with?(MANIFEST_FILENAME)

        current_dir = file.name.rpartition("/").first
        current_dir = nil if current_dir == ""

        current_depth = File.join(directory, file.name).split("/").count { |path| !path.empty? }
        path_to_directory = "../" * current_depth

        dep_types = FileParser::DEPENDENCY_TYPES
        parsed_manifest = JSON.parse(T.must(file.content))
        dependency_objects = parsed_manifest.values_at(*dep_types).compact
        # Fetch yarn "file:" path "resolutions" so the lockfile can be resolved
        resolution_objects = parsed_manifest.values_at("resolutions").compact
        manifest_objects = dependency_objects + resolution_objects

        raise Dependabot::DependencyFileNotParseable, file.path unless manifest_objects.all?(Hash)

        resolution_deps = resolution_objects.flat_map(&:to_a)
                                            .map do |path, value|
          # skip dependencies that contain invalid values such as inline comments, null, etc.

          unless value.is_a?(String)
            Dependabot.logger.warn("File fetcher: Skipping dependency \"#{path}\" " \
                                   "with value: \"#{value}\"")

            next
          end

          convert_dependency_path_to_name(path, value)
        end

        path_starts = PATH_DEPENDENCY_STARTS
        (dependency_objects.flat_map(&:to_a) + resolution_deps)
          .select { |_, v| v.is_a?(String) && v.start_with?(*path_starts) }
          .map do |name, path|
            path = path.gsub(PATH_DEPENDENCY_CLEAN_REGEX, "")
            raise PathDependenciesNotReachable, "#{name} at #{path}" if path.start_with?("/", "#{path_to_directory}..")

            path = File.join(current_dir, path) unless current_dir.nil?
            [name, Pathname.new(path).cleanpath.to_path]
          end
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, file.path
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(parsed_lockfile: T.untyped).returns(T::Array[[String, String]]) }
      def path_dependency_details_from_npm_lockfile(parsed_lockfile)
        path_starts = NPM_PATH_DEPENDENCY_STARTS
        parsed_lockfile.fetch("dependencies", []).to_a
                       .select { |_, v| v.is_a?(Hash) }
                       .select { |_, v| v.fetch("version", "").start_with?(*path_starts) }
                       .map { |k, v| [k, v.fetch("version")] }
      end

      # Re-write the glob name to the targeted dependency name (which is used
      # in the lockfile), for example "parent-package/**/sub-dep/target-dep" >
      # "target-dep"
      sig { params(path: String, value: String).returns([String, String]) }
      def convert_dependency_path_to_name(path, value)
        # Picking the last two parts that might include a scope
        parts = path.split("/").last(2)
        parts.shift if parts.count == 2 && !T.must(parts.first).start_with?("@")
        [parts.join("/"), value]
      end

      sig { returns(T::Array[DependencyFile]) }
      def fetch_workspace_package_jsons
        return [] unless parsed_package_json["workspaces"]

        workspace_paths(parsed_package_json["workspaces"]).filter_map do |workspace|
          fetch_package_json_if_present(workspace)
        end
      end

      sig { params(workspace_object: T.untyped).returns(T::Array[String]) }
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

      sig { params(glob: String).returns(T::Array[String]) }
      def find_directories(glob)
        return [glob] unless glob.include?("*")

        unglobbed_path =
          glob.gsub(%r{^\./}, "").gsub(/!\(.*?\)/, "*")
              .split("*")
              .first&.gsub(%r{(?<=/)[^/]*$}, "") || "."

        dir = directory.gsub(%r{(^/|/$)}, "")

        paths =
          repo_contents(dir: unglobbed_path, raise_errors: false)
          .select { |file| file.type == "dir" }
          .map { |f| f.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "") }

        matching_paths(glob, paths)
      end

      sig { params(glob: String, paths: T::Array[String]).returns(T::Array[String]) }
      def matching_paths(glob, paths)
        glob = glob.gsub(%r{^\./}, "").gsub(/!\(.*?\)/, "*")
        glob = "#{glob}/*" if glob.end_with?("**")

        paths.select { |filename| File.fnmatch?(glob, filename, File::FNM_PATHNAME) }
      end

      sig { params(glob: String, prefix: String).returns(T::Array[String]) }
      def recursive_find_directories(glob, prefix = "")
        return [prefix + glob] unless glob.include?("*")

        glob = glob.gsub(%r{^\./}, "")
        glob_parts = glob.split("/")

        current_glob = glob_parts.first
        paths = find_directories(prefix + T.must(current_glob))
        next_parts = current_glob == "**" ? glob_parts : glob_parts.drop(1)
        return paths if next_parts.empty?

        paths += paths.flat_map do |expanded_path|
          recursive_find_directories(next_parts.join("/"), "#{expanded_path}/")
        end

        matching_paths(prefix + glob, paths)
      end

      sig { params(workspace: String).returns(T.nilable(DependencyFile)) }
      def fetch_package_json_if_present(workspace)
        file = File.join(workspace, MANIFEST_FILENAME)

        begin
          fetch_file_from_host(file)
        rescue Dependabot::DependencyFileNotFound
          # Not all paths matched by a workspace glob may contain a package.json
          # file. Ignore if that's the case
          nil
        end
      end

      sig { returns(T.untyped) }
      def parsed_package_json
        parsed = JSON.parse(T.must(package_json.content))
        raise Dependabot::DependencyFileNotParseable, package_json.path unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, package_json.path
      end

      sig { params(filename: String).returns(T.nilable(DependencyFile)) }
      def fetch_file_with_support(filename)
        fetch_file_from_host(filename).tap { |f| f.support_file = true }
      rescue Dependabot::DependencyFileNotFound
        nil
      end

      sig { params(filename: String).returns(T.nilable(DependencyFile)) }
      def fetch_file_from_parent_directories(filename)
        (1..directory.split("/").count).each do |i|
          file = fetch_file_with_support(("../" * i) + filename)
          return file if file
        end
        nil
      end
    end
  end
end

Dependabot::FileFetchers
  .register(Dependabot::Bun::ECOSYSTEM, Dependabot::Bun::FileFetcher)
