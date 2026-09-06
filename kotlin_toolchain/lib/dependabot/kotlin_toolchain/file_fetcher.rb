# typed: strong
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/file_filtering"
require "dependabot/kotlin_toolchain/compatibility_profile"
require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/wrapper"
require "dependabot/kotlin_toolchain/yaml_parser"

module Dependabot
  module KotlinToolchain
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        basenames = filenames.map { |name| File.basename(name) }
        wrapper = basenames.any? { |name| WRAPPER_FILES.include?(name) }
        manifest = basenames.any? { |name| name == PROJECT_FILE || name == MODULE_FILE }
        wrapper && manifest
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a Kotlin Toolchain wrapper and a project.yaml or module.yaml file"
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Kotlin Toolchain support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
          )
        end

        files = T.let(verified_wrapper_files, T::Array[Dependabot::DependencyFile])

        project_file = fetch_root_file(PROJECT_FILE)
        root_module = fetch_root_file(MODULE_FILE)
        files << project_file if project_file
        files << root_module if root_module
        files.concat(fetch_module_files(project_file))
        files.concat(fetch_templates(files, CompatibilityProfile.for(Wrapper.detect_version(files))))
        files.concat(fetch_version_catalogs)

        files = files.uniq(&:name)
        ensure_manifest!(files)

        files
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.anything])) }
      def ecosystem_versions
        wrappers = wrapper_files
        return if wrappers.empty?

        { package_managers: { PACKAGE_MANAGER => Wrapper.detect_version(wrappers) } }
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def verified_wrapper_files
        files = wrapper_files
        raise Dependabot::DependencyFileNotFound.new(nil, "Kotlin Toolchain wrapper is missing") if files.empty?

        Wrapper.detect_version(files)
        Wrapper.detect_sha(files)
        Wrapper.detect_repository(files)
        files
      end

      sig { params(name: String).returns(T.nilable(Dependabot::DependencyFile)) }
      def fetch_root_file(name)
        return if excluded?(name)

        fetch_file_if_present(name)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def wrapper_files
        WRAPPER_FILES.filter_map do |name|
          next if excluded?(name)

          fetch_file_if_present(name)
        end
      end

      sig do
        params(
          project_file: T.nilable(Dependabot::DependencyFile)
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def fetch_module_files(project_file)
        return [] unless project_file

        module_paths(project_file).filter_map do |path|
          next if excluded?(path)

          fetch_file_if_present(path)
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_version_catalogs
        VERSION_CATALOG_PATHS.filter_map do |path|
          next if excluded?(path)

          fetch_file_if_present(path)
        end
      end

      sig { params(files: T::Array[Dependabot::DependencyFile]).void }
      def ensure_manifest!(files)
        return if files.any? { |file| kotlin_manifest?(file.name) }

        raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message)
      end

      sig { params(project_file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def module_paths(project_file)
        parsed = parsed_yaml(project_file)
        raw_modules = parsed["modules"]
        return [] unless raw_modules.is_a?(Array)

        raw_modules.grep(String)
                   .flat_map { |pattern| expand_module_pattern(pattern) }
                   .map { |path| path == "." ? MODULE_FILE : File.join(path, MODULE_FILE) }
                   .uniq
      end

      sig { params(pattern: String).returns(T::Array[String]) }
      def expand_module_pattern(pattern)
        path = Pathname.new(pattern.delete_prefix("./"))
        return [] if path.absolute?

        normalized = path.cleanpath.to_path.delete_suffix("/")
        return [] if normalized == ".." || normalized.start_with?("../")
        return [normalized] unless normalized.match?(/[*?\[]/)

        normalized.split("/").reduce(T.let([""], T::Array[String])) do |candidates, part|
          expand_module_pattern_part(candidates, part)
        end
      end

      sig { params(candidates: T::Array[String], part: String).returns(T::Array[String]) }
      def expand_module_pattern_part(candidates, part)
        candidates.flat_map do |base|
          next [join_path(base, part)] unless part.match?(/[*?\[]/)

          dir = base.empty? ? "." : base
          repo_contents(dir: dir, raise_errors: false).filter_map do |entry|
            name = entry.name
            next unless entry.type == "dir" && name && File.fnmatch?(part, name)

            join_path(base, name)
          end
        end
      end

      sig { params(base: String, name: String).returns(String) }
      def join_path(base, name)
        base.empty? ? name : File.join(base, name)
      end

      sig do
        params(
          files: T::Array[Dependabot::DependencyFile],
          profile: CompatibilityProfile
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def fetch_templates(files, profile)
        fetched = T.let([], T::Array[Dependabot::DependencyFile])
        queue = T.let(files.select { |file| module_manifest?(file.name) }, T::Array[Dependabot::DependencyFile])
        visited = T.let({}, T::Hash[String, T::Boolean])

        until queue.empty?
          declaring_file = T.must(queue.shift)
          next if visited[declaring_file.name]

          visited[declaring_file.name] = true
          template_paths(declaring_file).each do |path|
            next if excluded?(path)
            next if fetched.any? { |file| file.name == path }

            template = fetch_file_if_present(path)
            next unless template

            fetched << template
            queue << template if profile.nested_templates?
          end
        end

        fetched
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def template_paths(file)
        parsed = parsed_yaml(file)
        raw_apply = parsed["apply"]
        entries = case raw_apply
                  when String then [raw_apply]
                  when Array then raw_apply.grep(String)
                  else []
                  end

        entries.filter_map do |entry|
          path = if entry.start_with?("//")
                   entry.delete_prefix("//")
                 else
                   File.join(File.dirname(file.name), entry)
                 end
          normalized = Pathname.new(path).cleanpath.to_path.delete_prefix("./")
          next if normalized == ".." || normalized.start_with?("../")
          next unless normalized.end_with?(MODULE_TEMPLATE_SUFFIX)

          normalized
        end
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Hash[String, Object]) }
      def parsed_yaml(file)
        parsed = YamlParser.load(file.content.to_s, filename: file.name)
        return parsed if parsed.is_a?(Hash)

        {}
      end

      sig { params(path: String).returns(T::Boolean) }
      def excluded?(path)
        Dependabot::FileFiltering.should_exclude_path?(
          path,
          "Kotlin Toolchain file",
          @exclude_paths
        )
      end

      sig { params(name: String).returns(T::Boolean) }
      def kotlin_manifest?(name)
        basename = File.basename(name)
        basename == PROJECT_FILE || basename == MODULE_FILE
      end

      sig { params(name: String).returns(T::Boolean) }
      def module_manifest?(name)
        File.basename(name) == MODULE_FILE || name.end_with?(MODULE_TEMPLATE_SUFFIX)
      end
    end
  end
end

Dependabot::FileFetchers.register(
  "kotlin_toolchain",
  Dependabot::KotlinToolchain::FileFetcher
)
