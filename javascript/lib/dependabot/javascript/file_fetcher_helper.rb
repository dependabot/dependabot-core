# typed: strict
# frozen_string_literal: true

module Dependabot
  module Javascript
    module FileFetcherHelper
      include Kernel
      extend T::Sig

      PATH_DEPENDENCY_STARTS = T.let(%w(file: / ./ ../ ~/).freeze, [String, String, String, String, String])
      PATH_DEPENDENCY_CLEAN_REGEX = /^file:|^link:/
      DEPENDENCY_TYPES = T.let(%w(dependencies devDependencies optionalDependencies).freeze, T::Array[String])

      sig { params(instance: Dependabot::Javascript::Bun::FileFetcher).returns(T::Array[DependencyFile]) }
      def workspace_package_jsons(instance)
        @workspace_package_jsons ||= T.let(fetch_workspace_package_jsons(instance), T.nilable(T::Array[DependencyFile]))
      end

      sig do
        params(instance: Dependabot::Javascript::Bun::FileFetcher, fetched_files: T::Array[DependencyFile])
          .returns(T::Array[DependencyFile])
      end
      def path_dependencies(instance, fetched_files)
        package_json_files = T.let([], T::Array[DependencyFile])

        path_dependency_details(instance, fetched_files).each do |name, path|
          # This happens with relative paths in the package-lock. Skipping it since it results
          # in /package.json which is outside of the project directory.
          next if path == "file:"

          path = path.gsub(PATH_DEPENDENCY_CLEAN_REGEX, "")
          raise PathDependenciesNotReachable, "#{name} at #{path}" if path.start_with?("/")

          filename = path
          filename = File.join(filename, MANIFEST_FILENAME)
          cleaned_name = Pathname.new(filename).cleanpath.to_path
          next if fetched_files.map(&:name).include?(cleaned_name)

          file = instance.fetch_file(filename, fetch_submodules: true)
          package_json_files << file
        end

        if package_json_files.any?
          package_json_files +=
            path_dependencies(instance, fetched_files + package_json_files)
        end

        package_json_files.tap { |fs| fs.each { |f| f.support_file = true } }
      end

      sig do
        params(instance: Dependabot::Javascript::Bun::FileFetcher, fetched_files: T::Array[DependencyFile])
          .returns(T::Array[[String, String]])
      end
      def path_dependency_details(instance, fetched_files)
        package_json_path_deps = T.let([], T::Array[[String, String]])

        fetched_files.each do |file|
          package_json_path_deps +=
            path_dependency_details_from_manifest(instance, file)
        end

        [
          *package_json_path_deps
        ].uniq
      end

      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      sig do
        params(instance: Dependabot::Javascript::Bun::FileFetcher,
               file: DependencyFile).returns(T::Array[[String, String]])
      end
      def path_dependency_details_from_manifest(instance, file)
        return [] unless file.name.end_with?(MANIFEST_FILENAME)

        current_dir = file.name.rpartition("/").first
        current_dir = nil if current_dir == ""

        current_depth = File.join(instance.directory, file.name).split("/").count { |path| !path.empty? }
        path_to_directory = "../" * current_depth

        dep_types = DEPENDENCY_TYPES # TODO: Is this needed?
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

      sig { params(instance: Dependabot::Javascript::Bun::FileFetcher).returns(T::Array[DependencyFile]) }
      def fetch_workspace_package_jsons(instance)
        parsed_manifest = parsed_package_json(instance)
        return [] unless parsed_manifest["workspaces"]

        workspace_paths(instance, parsed_manifest["workspaces"]).filter_map do |workspace|
          fetch_package_json_if_present(instance, workspace)
        end
      end

      sig do
        params(instance: Dependabot::Javascript::Bun::FileFetcher,
               workspace_object: T.untyped).returns(T::Array[String])
      end
      def workspace_paths(instance, workspace_object)
        paths_array =
          if workspace_object.is_a?(Hash)
            workspace_object.values_at("packages", "nohoist").flatten.compact
          elsif workspace_object.is_a?(Array) then workspace_object
          else
            [] # Invalid lerna.json, which must not be in use
          end

        paths_array.flat_map { |path| recursive_find_directories(instance, path) }
      end

      sig { params(instance: Dependabot::Javascript::Bun::FileFetcher, glob: String).returns(T::Array[String]) }
      def find_directories(instance, glob)
        return [glob] unless glob.include?("*")

        unglobbed_path =
          glob.gsub(%r{^\./}, "").gsub(/!\(.*?\)/, "*")
              .split("*")
              .first&.gsub(%r{(?<=/)[^/]*$}, "") || "."

        dir = instance.directory.gsub(%r{(^/|/$)}, "")

        paths =
          instance.fetch_repo_contents(dir: unglobbed_path, raise_errors: false)
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

      sig do
        params(instance: Dependabot::Javascript::Bun::FileFetcher, glob: String,
               prefix: String).returns(T::Array[String])
      end
      def recursive_find_directories(instance, glob, prefix = "")
        return [prefix + glob] unless glob.include?("*")

        glob = glob.gsub(%r{^\./}, "")
        glob_parts = glob.split("/")

        current_glob = glob_parts.first
        paths = find_directories(instance, prefix + T.must(current_glob))
        next_parts = current_glob == "**" ? glob_parts : glob_parts.drop(1)
        return paths if next_parts.empty?

        paths += paths.flat_map do |expanded_path|
          recursive_find_directories(instance, next_parts.join("/"), "#{expanded_path}/")
        end

        matching_paths(prefix + glob, paths)
      end

      sig do
        params(instance: Dependabot::Javascript::Bun::FileFetcher, workspace: String).returns(T.nilable(DependencyFile))
      end
      def fetch_package_json_if_present(instance, workspace)
        file = File.join(workspace, MANIFEST_FILENAME)

        begin
          instance.fetch_file(file)
        rescue Dependabot::DependencyFileNotFound
          # Not all paths matched by a workspace glob may contain a package.json
          # file. Ignore if that's the case
          nil
        end
      end

      sig { params(instance: Dependabot::Javascript::Bun::FileFetcher).returns(DependencyFile) }
      def package_json(instance)
        @package_json ||= T.let(instance.fetch_file(Javascript::MANIFEST_FILENAME), T.nilable(DependencyFile))
      end

      sig { params(instance: Dependabot::Javascript::Bun::FileFetcher).returns(T.untyped) }
      def parsed_package_json(instance)
        manifest_file = package_json(instance)
        parsed = JSON.parse(T.must(manifest_file.content))
        raise Dependabot::DependencyFileNotParseable, manifest_file.path unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, T.must(manifest_file).path
      end

      sig do
        params(instance: Dependabot::Javascript::Bun::FileFetcher, filename: String).returns(T.nilable(DependencyFile))
      end
      def fetch_file_with_support(instance, filename)
        instance.fetch_file(filename).tap { |f| f.support_file = true }
      rescue Dependabot::DependencyFileNotFound
        nil
      end

      sig do
        params(instance: Dependabot::Javascript::Bun::FileFetcher, filename: String).returns(T.nilable(DependencyFile))
      end
      def fetch_file_from_parent_directories(instance, filename)
        (1..instance.directory.split("/").count).each do |i|
          file = fetch_file_with_support(instance, ("../" * i) + filename)
          return file if file
        end
        nil
      end
    end
  end
end
