# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/python/language_version_manager"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_parser/pyproject_files_parser"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/errors"
require "dependabot/file_filtering"

module Dependabot
  module Python
    class SharedFileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      abstract!

      CHILD_REQUIREMENT_REGEX = T.let(/^-r\s?(?<path>.*\.(?:txt|in))/, Regexp)
      CONSTRAINT_REGEX = T.let(/^-c\s?(?<path>.*\.(?:txt|in))/, Regexp)
      DEPENDENCY_TYPES = T.let(%w(packages dev-packages).freeze, T::Array[String])
      MAX_FILE_SIZE = T.let(500_000, Integer)

      sig { abstract.returns(T::Array[String]) }
      def self.ecosystem_specific_required_files; end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        return true if filenames.any? { |name| name.end_with?(".txt", ".in") }
        return true if filenames.include?("requirements")
        return true if filenames.include?("pyproject.toml")
        return true if filenames.any? { |name| ecosystem_specific_required_files.include?(name) }

        false
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        python_requirement_parser = FileParser::PythonRequirementParser.new(dependency_files: files)
        language_version_manager = LanguageVersionManager.new(python_requirement_parser: python_requirement_parser)
        Dependabot.logger.info("Dependabot is using Python version '#{language_version_manager.python_version}'.")
        {
          languages: {
            python: {
              "raw" => language_version_manager.user_specified_python_version || "unknown",
              "max" => language_version_manager.python_major_minor || "unknown"
            }
          }
        }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []

        fetched_files += ecosystem_specific_files
        fetched_files += pyproject_files

        fetched_files += requirements_in_files
        fetched_files += requirement_files if requirements_txt_files.any?

        fetched_files += project_files
        fetched_files << python_version_file if python_version_file

        uniques = uniq_files(fetched_files)
        uniques.reject do |file|
          Dependabot::FileFiltering.should_exclude_path?(file.name, "file from final collection", @exclude_paths)
        end
      end

      private

      sig { abstract.returns(T::Array[Dependabot::DependencyFile]) }
      def ecosystem_specific_files; end

      sig { abstract.returns(T::Array[Dependabot::DependencyFile]) }
      def pyproject_files; end

      sig { abstract.returns(T::Array[T::Hash[Symbol, String]]) }
      def path_dependencies; end

      sig { abstract.returns(T::Array[String]) }
      def additional_path_dependencies; end

      sig { abstract.params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def lockfile_for_compile_file?(file); end

      sig { abstract.params(path: String).returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_project_file(path); end

      sig { params(fetched_files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile]) }
      def uniq_files(fetched_files)
        uniq_files = fetched_files.reject(&:support_file?).uniq
        uniq_files += fetched_files
                      .reject { |f| uniq_files.map(&:name).include?(f.name) }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def requirement_files
        [
          *requirements_txt_files,
          *child_requirement_txt_files,
          *constraints_files
        ]
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def python_version_file
        return @python_version_file if defined?(@python_version_file)

        @python_version_file = T.let(
          begin
            file = fetch_support_file(".python-version")
            return file if file
            return if [".", "/"].include?(directory)

            # Check the top-level for a .python-version file, too
            reverse_path = Pathname.new(directory[0]).relative_path_from(directory)
            fetch_support_file(File.join(reverse_path, ".python-version"))
              &.tap { |f| f.name = ".python-version" }
          end,
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pyproject
        return @pyproject if defined?(@pyproject)

        @pyproject = T.let(
          fetch_file_if_present("pyproject.toml"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def requirements_txt_files
        req_txt_and_in_files.select { |f| f.name.end_with?(".txt") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def requirements_in_files
        req_txt_and_in_files.select { |f| f.name.end_with?(".in") } +
          child_requirement_in_files
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_pyproject
        raise "No pyproject.toml" unless pyproject

        @parsed_pyproject ||= T.let(
          TomlRB.parse(T.must(pyproject).content),
          T.nilable(T::Hash[String, T.untyped])
        )
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, T.must(pyproject).path
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def req_txt_and_in_files
        @req_txt_and_in_files ||= T.let(
          begin
            files = T.let([], T::Array[Dependabot::DependencyFile])

            repo_contents
              .select { |f| f.type == "file" }
              .select { |f| f.name.end_with?(".txt", ".in") }
              .reject { |f| f.size > MAX_FILE_SIZE }
              .map { |f| fetch_file_from_host(f.name) }
              .select { |f| requirements_file?(f) }
              .each { |f| files << f }

            repo_contents
              .select { |f| f.type == "dir" }
              .each { |f| files.concat(req_files_for_dir(f)) }

            files
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { params(requirements_dir: T.untyped).returns(T::Array[Dependabot::DependencyFile]) }
      def req_files_for_dir(requirements_dir)
        dir = directory.gsub(%r{(^/|/$)}, "")
        relative_reqs_dir =
          requirements_dir.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "")

        repo_contents(dir: relative_reqs_dir)
          .select { |f| f.type == "file" }
          .select { |f| f.name.end_with?(".txt", ".in") }
          .reject { |f| f.size > MAX_FILE_SIZE }
          .map { |f| fetch_file_from_host("#{relative_reqs_dir}/#{f.name}") }
          .select { |f| requirements_file?(f) }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def child_requirement_txt_files
        child_requirement_files.select { |f| f.name.end_with?(".txt") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def child_requirement_in_files
        child_requirement_files.select { |f| f.name.end_with?(".in") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def child_requirement_files
        @child_requirement_files ||= T.let(
          begin
            fetched_files = req_txt_and_in_files.dup
            req_txt_and_in_files.flat_map do |requirement_file|
              child_files = fetch_child_requirement_files(
                file: requirement_file,
                previously_fetched_files: fetched_files
              )

              fetched_files += child_files
              child_files
            end
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          previously_fetched_files: T::Array[Dependabot::DependencyFile]
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def fetch_child_requirement_files(file:, previously_fetched_files:)
        content = file.content
        return [] if content.nil?

        paths = content.scan(CHILD_REQUIREMENT_REGEX).flatten
        current_dir = File.dirname(file.name)

        paths.flat_map do |path|
          path = File.join(current_dir, path) unless current_dir == "."
          path = clean_path(path)

          next if previously_fetched_files.map(&:name).include?(path)
          next if file.name == path

          if Dependabot::Experiments.enabled?(:enable_exclude_paths_subdirectory_manifest_files) &&
             !@exclude_paths.empty? && Dependabot::FileFiltering.exclude_path?(path, @exclude_paths)
            raise Dependabot::DependencyFileNotEvaluatable,
                  "Cannot process requirements: '#{file.name}' references excluded file '#{path}'. " \
                  "Please either remove the reference from '#{file.name}' " \
                  "or update your exclude_paths configuration."
          end

          fetched_file = fetch_file_from_host(path)
          grandchild_requirement_files = fetch_child_requirement_files(
            file: fetched_file,
            previously_fetched_files: previously_fetched_files + [file]
          )
          [fetched_file, *grandchild_requirement_files]
        end.compact
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def constraints_files
        all_requirement_files = requirements_txt_files +
                                child_requirement_txt_files

        constraints_paths = all_requirement_files.map do |req_file|
          current_dir = File.dirname(req_file.name)
          content = req_file.content
          next [] if content.nil?

          paths = content.scan(CONSTRAINT_REGEX).flatten

          paths.map do |path|
            path = File.join(current_dir, path) unless current_dir == "."
            clean_path(path)
          end
        end.flatten.uniq

        constraints_paths.map { |path| fetch_file_from_host(path) }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def project_files
        project_files = T.let([], T::Array[Dependabot::DependencyFile])
        unfetchable_deps = []

        path_dependencies.each do |dep|
          path = dep[:path]
          next if path.nil?

          project_files += fetch_project_file(path)
        rescue Dependabot::DependencyFileNotFound
          next if sdist_or_wheel?(T.must(path))

          unfetchable_deps << "\"#{dep[:name]}\" at #{clean_path(File.join(directory, dep[:file]))}"
        end

        additional_path_dependencies.each do |path|
          project_files += fetch_project_file(path)
        rescue Dependabot::DependencyFileNotFound => e
          unfetchable_deps << e.file_path&.gsub(%r{^/}, "")
        end

        raise Dependabot::PathDependenciesNotReachable, unfetchable_deps if unfetchable_deps.any?

        project_files
      end

      sig { params(path: String).returns(T::Boolean) }
      def sdist_or_wheel?(path)
        path.end_with?(".tar.gz", ".whl", ".zip")
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def requirements_file?(file)
        return false unless file.content&.valid_encoding?
        return true if file.name.match?(/requirements/x)

        T.must(file.content).lines.all? do |line|
          next true if line.strip.empty?
          next true if line.strip.start_with?("#", "-r ", "-c ", "-e ", "--")

          line.match?(RequirementParser::VALID_REQ_TXT_REQUIREMENT)
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def requirement_txt_path_dependencies
        (requirements_txt_files + child_requirement_txt_files)
          .map { |req_file| parse_requirement_path_dependencies(req_file) }
          .flatten.uniq { |dep| dep[:path] }
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def requirement_in_path_dependencies
        requirements_in_files
          .map { |req_file| parse_requirement_path_dependencies(req_file) }
          .flatten.uniq { |dep| dep[:path] }
      end

      sig { params(req_file: Dependabot::DependencyFile).returns(T::Array[T::Hash[Symbol, String]]) }
      def parse_requirement_path_dependencies(req_file)
        # If this is a pip-compile lockfile, rely on whatever path dependencies we found in the main manifest
        return [] if lockfile_for_compile_file?(req_file)

        content = req_file.content
        return [] if content.nil?

        uneditable_reqs =
          content
          .scan(/(?<name>^['"]?(?:file:)?(?<path>\.[^\[#'"\n]*))/)
          .filter_map do |match_array|
            n, p = match_array
            { name: n.to_s.strip, path: p.to_s.strip, file: req_file.name } unless p.to_s.include?("://")
          end

        editable_reqs =
          content
          .scan(/(?<name>^-e\s+['"]?(?:file:)?(?<path>[^\[#'"\n]*))/)
          .filter_map do |match_array|
            n, p = match_array
            unless p.to_s.include?("://") || p.to_s.include?("git@")
              { name: n.to_s.strip, path: p.to_s.strip, file: req_file.name }
            end
          end

        uneditable_reqs + editable_reqs
      end

      sig { params(path: String).returns(String) }
      def clean_path(path)
        Pathname.new(path).cleanpath.to_path
      end
    end
  end
end
