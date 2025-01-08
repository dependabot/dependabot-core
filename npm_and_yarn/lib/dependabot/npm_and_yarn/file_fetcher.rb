# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/experiments"
require "dependabot/logger"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/package_manager"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser"

module Dependabot
  module NpmAndYarn
    class FileFetcher < Dependabot::FileFetchers::Base # rubocop:disable Metrics/ClassLength
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

      # Overridden to pull any yarn data or plugins which may be stored with Git LFS.
      sig { override.returns(String) }
      def clone_repo_contents
        return @git_lfs_cloned_repo_contents_path unless @git_lfs_cloned_repo_contents_path.nil?

        @git_lfs_cloned_repo_contents_path ||= T.let(super, T.nilable(String))
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

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        package_managers = {}

        package_managers["npm"] = npm_version if npm_version
        package_managers["yarn"] = yarn_version if yarn_version
        package_managers["pnpm"] = pnpm_version if pnpm_version
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
        fetched_files += npm_files if npm_version
        fetched_files += yarn_files if yarn_version
        fetched_files += pnpm_files if pnpm_version
        fetched_files += bun_files if bun_version
        fetched_files += lerna_files
        fetched_files += workspace_package_jsons
        fetched_files += path_dependencies(fetched_files)

        fetched_files.uniq
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def npm_files
        fetched_npm_files = []
        fetched_npm_files << package_lock if package_lock && !skip_package_lock?
        fetched_npm_files << shrinkwrap if shrinkwrap
        fetched_npm_files << inferred_npmrc if inferred_npmrc
        fetched_npm_files
      end

      sig { returns(T::Array[DependencyFile]) }
      def yarn_files
        fetched_yarn_files = []
        fetched_yarn_files << yarn_lock if yarn_lock
        fetched_yarn_files << yarnrc if yarnrc
        fetched_yarn_files << yarnrc_yml if yarnrc_yml
        create_yarn_cache
        fetched_yarn_files
      end

      sig { returns(T::Array[DependencyFile]) }
      def pnpm_files
        fetched_pnpm_files = []
        fetched_pnpm_files << pnpm_lock if pnpm_lock && !skip_pnpm_lock?
        fetched_pnpm_files << pnpm_workspace_yaml if pnpm_workspace_yaml
        fetched_pnpm_files += pnpm_workspace_package_jsons
        fetched_pnpm_files
      end

      sig { returns(T::Array[DependencyFile]) }
      def bun_files
        fetched_bun_files = []
        fetched_bun_files << bun_lock if bun_lock
        fetched_bun_files
      end

      sig { returns(T::Array[DependencyFile]) }
      def lerna_files
        fetched_lerna_files = []
        fetched_lerna_files << lerna_json if lerna_json
        fetched_lerna_files += lerna_packages
        fetched_lerna_files
      end

      # If every entry in the lockfile uses the same registry, we can infer
      # that there is a global .npmrc file, so add it here as if it were in the repo.

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(T.nilable(DependencyFile)) }
      def inferred_npmrc # rubocop:disable Metrics/PerceivedComplexity
        return @inferred_npmrc if defined?(@inferred_npmrc)
        return @inferred_npmrc ||= T.let(nil, T.nilable(DependencyFile)) unless npmrc.nil? && package_lock

        known_registries = []
        FileParser::JsonLock.new(T.must(package_lock)).parsed.fetch("dependencies",
                                                                    {}).each do |dependency_name, details|
          resolved = details.fetch("resolved", DEFAULT_NPM_REGISTRY)

          begin
            uri = URI.parse(resolved)
          rescue URI::InvalidURIError
            # Ignoring non-URIs since they're not registries.
            # This can happen if resolved is `false`, for instance
            # npm6 bug https://github.com/npm/cli/issues/1138
            next
          end

          next unless uri.scheme && uri.host

          known_registry = "#{uri.scheme}://#{uri.host}"
          path = uri.path

          next unless path

          index = path.index(dependency_name)
          if index
            registry_base_path = T.must(path[0...index]).delete_suffix("/")
            known_registry << registry_base_path
          end

          known_registries << known_registry
        end

        if known_registries.uniq.length == 1 && known_registries.first != DEFAULT_NPM_REGISTRY
          Dependabot.logger.info("Inferred global NPM registry is: #{known_registries.first}")
          return @inferred_npmrc ||= Dependabot::DependencyFile.new(
            name: ".npmrc",
            content: "registry=#{known_registries.first}"
          )
        end

        @inferred_npmrc ||= nil
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/PerceivedComplexity

      sig { returns(T.nilable(T.any(Integer, String))) }
      def npm_version
        @npm_version ||= T.let(package_manager_helper.setup(NpmPackageManager::NAME), T.nilable(T.any(Integer, String)))
      end

      sig { returns(T.nilable(T.any(Integer, String))) }
      def yarn_version
        @yarn_version ||= T.let(
          package_manager_helper.setup(YarnPackageManager::NAME),
          T.nilable(T.any(Integer, String))
        )
      end

      sig { returns(T.nilable(T.any(Integer, String))) }
      def pnpm_version
        @pnpm_version ||= T.let(
          package_manager_helper.setup(PNPMPackageManager::NAME),
          T.nilable(T.any(Integer, String))
        )
      end

      sig { returns(T.nilable(T.any(Integer, String))) }
      def bun_version
        @bun_version ||= T.let(
          package_manager_helper.setup(Bun::NAME),
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
          npm: package_lock || shrinkwrap,
          yarn: yarn_lock,
          pnpm: pnpm_lock,
          bun: bun_lock
        }
      end

      # Returns the .npmrc, and .yarnrc files for the repository.
      # @return [Hash{Symbol => Dependabot::DependencyFile}]
      sig { returns(T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)]) }
      def registry_config_files
        {
          npmrc: npmrc,
          yarnrc: yarnrc,
          yarnrc_yml: yarnrc_yml
        }
      end

      sig { returns(DependencyFile) }
      def package_json
        @package_json ||= T.let(fetch_file_from_host(MANIFEST_FILENAME), T.nilable(DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def package_lock
        return @package_lock if defined?(@package_lock)

        @package_lock ||= T.let(fetch_file_if_present(NpmPackageManager::LOCKFILE_NAME), T.nilable(DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def yarn_lock
        return @yarn_lock if defined?(@yarn_lock)

        @yarn_lock ||= T.let(fetch_file_if_present(YarnPackageManager::LOCKFILE_NAME), T.nilable(DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def pnpm_lock
        return @pnpm_lock if defined?(@pnpm_lock)

        @pnpm_lock ||= T.let(fetch_file_if_present(PNPMPackageManager::LOCKFILE_NAME), T.nilable(DependencyFile))

        return @pnpm_lock if @pnpm_lock || directory == "/"

        @pnpm_lock = fetch_file_from_parent_directories(PNPMPackageManager::LOCKFILE_NAME)
      end

      sig { returns(T.nilable(DependencyFile)) }
      def bun_lock
        return @bun_lock if defined?(@bun_lock)

        @bun_lock ||= T.let(fetch_file_if_present(Bun::LOCKFILE_NAME), T.nilable(DependencyFile))

        return @bun_lock if @bun_lock || directory == "/"

        @bun_lock = fetch_file_from_parent_directories(Bun::LOCKFILE_NAME)
      end

      sig { returns(T.nilable(DependencyFile)) }
      def shrinkwrap
        return @shrinkwrap if defined?(@shrinkwrap)

        @shrinkwrap ||= T.let(
          fetch_file_if_present(
            NpmPackageManager::SHRINKWRAP_LOCKFILE_NAME
          ),
          T.nilable(DependencyFile)
        )
      end

      sig { returns(T.nilable(DependencyFile)) }
      def npmrc
        return @npmrc if defined?(@npmrc)

        @npmrc ||= T.let(fetch_support_file(NpmPackageManager::RC_FILENAME), T.nilable(DependencyFile))

        return @npmrc if @npmrc || directory == "/"

        @npmrc = fetch_file_from_parent_directories(NpmPackageManager::RC_FILENAME)
      end

      sig { returns(T.nilable(DependencyFile)) }
      def yarnrc
        return @yarnrc if defined?(@yarnrc)

        @yarnrc ||= T.let(fetch_support_file(YarnPackageManager::RC_FILENAME), T.nilable(DependencyFile))

        return @yarnrc if @yarnrc || directory == "/"

        @yarnrc = fetch_file_from_parent_directories(YarnPackageManager::RC_FILENAME)
      end

      sig { returns(T.nilable(DependencyFile)) }
      def yarnrc_yml
        @yarnrc_yml ||= T.let(fetch_support_file(YarnPackageManager::RC_YML_FILENAME), T.nilable(DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def pnpm_workspace_yaml
        return @pnpm_workspace_yaml if defined?(@pnpm_workspace_yaml)

        @pnpm_workspace_yaml = T.let(
          fetch_support_file(PNPMPackageManager::PNPM_WS_YML_FILENAME),
          T.nilable(DependencyFile)
        )
      end

      sig { returns(T.nilable(DependencyFile)) }
      def lerna_json
        return @lerna_json if defined?(@lerna_json)

        @lerna_json = T.let(fetch_support_file(LERNA_JSON_FILENAME), T.nilable(DependencyFile))
      end

      sig { returns(T::Array[DependencyFile]) }
      def workspace_package_jsons
        @workspace_package_jsons ||= T.let(fetch_workspace_package_jsons, T.nilable(T::Array[DependencyFile]))
      end

      sig { returns(T::Array[DependencyFile]) }
      def lerna_packages
        @lerna_packages ||= T.let(fetch_lerna_packages, T.nilable(T::Array[DependencyFile]))
      end

      sig { returns(T::Array[DependencyFile]) }
      def pnpm_workspace_package_jsons
        @pnpm_workspace_package_jsons ||= T.let(fetch_pnpm_workspace_package_jsons, T.nilable(T::Array[DependencyFile]))
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

        package_json_files += build_unfetchable_deps(unfetchable_deps)

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

      sig { returns(T::Array[DependencyFile]) }
      def fetch_lerna_packages
        return [] unless parsed_lerna_json["packages"]

        workspace_paths(parsed_lerna_json["packages"]).flat_map do |workspace|
          fetch_lerna_packages_from_path(workspace)
        end.compact
      end

      sig { returns(T::Array[DependencyFile]) }
      def fetch_pnpm_workspace_package_jsons
        return [] unless parsed_pnpm_workspace_yaml["packages"]

        workspace_paths(parsed_pnpm_workspace_yaml["packages"]).filter_map do |workspace|
          fetch_package_json_if_present(workspace)
        end
      end

      sig { params(path: String).returns(T::Array[T.nilable(DependencyFile)]) }
      def fetch_lerna_packages_from_path(path)
        package_json = fetch_package_json_if_present(path)
        return [] unless package_json

        [package_json] + [
          fetch_file_if_present(File.join(path, NpmPackageManager::LOCKFILE_NAME)),
          fetch_file_if_present(File.join(path, YarnPackageManager::LOCKFILE_NAME)),
          fetch_file_if_present(File.join(path, NpmPackageManager::SHRINKWRAP_LOCKFILE_NAME))
        ]
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
        return [glob] unless glob.include?("*") || yarn_ignored_glob(glob)

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
        ignored_glob = yarn_ignored_glob(glob)
        glob = glob.gsub(%r{^\./}, "").gsub(/!\(.*?\)/, "*")
        glob = "#{glob}/*" if glob.end_with?("**")

        results = paths.select { |filename| File.fnmatch?(glob, filename, File::FNM_PATHNAME) }
        return results unless ignored_glob

        results.reject { |filename| File.fnmatch?(ignored_glob, filename, File::FNM_PATHNAME) }
      end

      sig { params(glob: String, prefix: String).returns(T::Array[String]) }
      def recursive_find_directories(glob, prefix = "")
        return [prefix + glob] unless glob.include?("*") || yarn_ignored_glob(glob)

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

      # The packages/!(not-this-package) syntax is unique to Yarn
      sig { params(glob: String).returns(T.any(String, FalseClass)) }
      def yarn_ignored_glob(glob)
        glob.match?(/!\(.*?\)/) && glob.gsub(/(!\((.*?)\))/, '\2')
      end

      sig { returns(T.untyped) }
      def parsed_package_json
        parsed = JSON.parse(T.must(package_json.content))
        raise Dependabot::DependencyFileNotParseable, package_json.path unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, package_json.path
      end

      sig { returns(T.untyped) }
      def parsed_package_lock
        return {} unless package_lock

        JSON.parse(T.must(T.must(package_lock).content))
      rescue JSON::ParserError
        {}
      end

      sig { returns(T.untyped) }
      def parsed_shrinkwrap
        return {} unless shrinkwrap

        JSON.parse(T.must(T.must(shrinkwrap).content))
      rescue JSON::ParserError
        {}
      end

      sig { returns(T.untyped) }
      def parsed_pnpm_workspace_yaml
        return {} unless pnpm_workspace_yaml

        YAML.safe_load(T.must(T.must(pnpm_workspace_yaml).content))
      rescue Psych::SyntaxError
        raise Dependabot::DependencyFileNotParseable, T.must(pnpm_workspace_yaml).path
      end

      sig { returns(T::Boolean) }
      def skip_package_lock?
        return false unless npmrc

        T.must(T.must(npmrc).content).match?(/^package-lock\s*=\s*false/)
      end

      sig { returns(T::Boolean) }
      def skip_pnpm_lock?
        return false unless npmrc

        T.must(T.must(npmrc).content).match?(/^lockfile\s*=\s*false/)
      end

      sig { params(unfetchable_deps: T::Array[[String, String]]).returns(T::Array[DependencyFile]) }
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

      sig { returns(T.untyped) }
      def parsed_lerna_json
        return {} unless lerna_json

        JSON.parse(T.must(T.must(lerna_json).content))
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, T.must(lerna_json).path
      end

      sig { void }
      def create_yarn_cache
        if repo_contents_path.nil?
          Dependabot.logger.info("Repository contents path is nil")
        elsif Dir.exist?(T.must(repo_contents_path))
          Dir.chdir(T.must(repo_contents_path)) do
            FileUtils.mkdir_p(".yarn/cache")
          end
        else
          Dependabot.logger.info("Repository contents path does not exist")
        end
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
  .register(Dependabot::NpmAndYarn::ECOSYSTEM, Dependabot::NpmAndYarn::FileFetcher)
