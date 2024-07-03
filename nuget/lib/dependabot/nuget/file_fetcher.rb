# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/nuget/cache_manager"
require "set"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      require_relative "file_fetcher/import_paths_finder"
      require_relative "file_fetcher/sln_project_paths_finder"

      BUILD_FILE_NAMES = /^Directory\.Build\.(props|targets)$/i # Directory.Build.props, Directory.Build.targets

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        return true if filenames.any? { |f| f.match?(/^packages\.config$/i) }
        return true if filenames.any? { |f| f.end_with?(".sln") }
        return true if filenames.any? { |f| f.match?("^src$") }
        return true if filenames.any? { |f| f.end_with?(".proj") }

        filenames.any? { |name| name.match?(/\.(cs|vb|fs)proj$/) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a .proj file, .(cs|vb|fs)proj file, or a packages.config."
      end

      sig do
        override
          .params(
            source: Dependabot::Source,
            credentials: T::Array[Credential],
            repo_contents_path: T.nilable(String),
            options: T::Hash[String, String]
          ).void
      end
      def initialize(source:, credentials:, repo_contents_path: nil, options: {})
        super(source: source, credentials: credentials, repo_contents_path: repo_contents_path, options: options)

        @sln_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
        @sln_project_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
        @project_files = T.let([], T::Array[Dependabot::DependencyFile])
        @fetched_files = T.let({}, T::Hash[String, T::Array[Dependabot::DependencyFile]])
        @nuget_config_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
        @packages_config_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files += project_files
        fetched_files += directory_build_files
        fetched_files += imported_property_files

        fetched_files += packages_config_files
        fetched_files += nuget_config_files
        fetched_files << global_json if global_json
        fetched_files << dotnet_tools_json if dotnet_tools_json
        fetched_files << packages_props if packages_props

        # dedup files based on their absolute path
        fetched_files = fetched_files.uniq do |fetched_file|
          Pathname.new(fetched_file.directory).join(fetched_file.name).cleanpath.to_path
        end

        if project_files.none? && packages_config_files.none?
          raise T.must(@missing_sln_project_file_errors.first) if @missing_sln_project_file_errors&.any?

          raise_dependency_file_not_found
        end

        fetched_files
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def project_files
        return @project_files if @project_files.any?

        @project_files =
          begin
            project_files = []
            project_files += csproj_file
            project_files += vbproj_file
            project_files += fsproj_file
            project_files += sln_project_files
            project_files += proj_files
            project_files += project_files.filter_map do |f|
              named_file_up_tree_from_project_file(f, "Directory.Packages.props")
            end
            project_files
          end
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        raise_dependency_file_not_found
      end

      sig { returns(T.noreturn) }
      def raise_dependency_file_not_found
        raise(
          Dependabot::DependencyFileNotFound.new(
            File.join(directory, "*.(sln|csproj|vbproj|fsproj|proj)"),
            "Unable to find `*.sln`, `*.(cs|vb|fs)proj`, or `*.proj` in directory `#{directory}`"
          )
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def packages_config_files
        return @packages_config_files if @packages_config_files

        candidate_paths =
          [*project_files.map { |f| File.dirname(f.name) }, "."].uniq

        @packages_config_files =
          candidate_paths.filter_map do |dir|
            file = repo_contents(dir: dir)
                   .find { |f| f.name.casecmp("packages.config").zero? }
            fetch_file_from_host(File.join(dir, file.name)) if file
          end
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(T.nilable(T::Array[T.untyped])) }
      def sln_file_names
        sln_files = repo_contents.select { |f| f.name.end_with?(".sln") }
        src_dir = repo_contents.any? { |f| f.name == "src" && f.type == "dir" }

        # If there are no sln files but there is a src directory, check that dir
        if sln_files.none? && src_dir
          sln_files = repo_contents(dir: "src")
                      .select { |f| f.name.end_with?(".sln") }.map(&:dup)
                      .map { |file| file.tap { |f| f.name = "src/" + f.name } }
        end

        # Return `nil` if no sln files were found
        return if sln_files.none?

        sln_files.map(&:name)
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def directory_build_files
        @directory_build_files ||= T.let(fetch_directory_build_files, T.nilable(T::Array[Dependabot::DependencyFile]))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_directory_build_files
        attempted_dirs = T.let([], T::Array[Pathname])
        directory_build_files = T.let([], T::Array[Dependabot::DependencyFile])
        directory_path = Pathname.new(directory)

        # find all build files (Directory.Build.props/.targets) relative to the given project file
        project_files.map { |f| Pathname.new(f.directory).join(f.name).dirname }.uniq.each do |dir|
          # Simulate MSBuild walking up the directory structure looking for a file
          dir.descend.each do |possible_dir|
            break if attempted_dirs.include?(possible_dir)

            attempted_dirs << possible_dir
            relative_possible_dir = Pathname.new(possible_dir).relative_path_from(directory_path).to_s
            build_files = repo_contents(dir: relative_possible_dir).select { |f| f.name.match?(BUILD_FILE_NAMES) }
            directory_build_files += build_files.map do |file|
              possible_file = File.join(relative_possible_dir, file.name).delete_prefix("/")
              fetch_file_from_host(possible_file)
            end
          end
        end

        directory_build_files
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def sln_project_files
        return [] unless sln_files

        @sln_project_files ||=
          begin
            paths = T.must(sln_files).flat_map do |sln_file|
              SlnProjectPathsFinder
                .new(sln_file: sln_file)
                .project_paths
            end

            paths.filter_map do |path|
              fetch_file_from_host(path)
            rescue Dependabot::DependencyFileNotFound => e
              @missing_sln_project_file_errors ||= T.let([], T.nilable(T::Array[Dependabot::DependencyFileNotFound]))
              @missing_sln_project_file_errors << e
              # Don't worry about missing files too much for now (at least
              # until we start resolving properties)
              nil
            end
          end
      end

      sig { returns(T.nilable(T::Array[Dependabot::DependencyFile])) }
      def sln_files
        return unless sln_file_names

        @sln_files ||=
          sln_file_names
          &.map { |sln_file_name| fetch_file_from_host(sln_file_name) }
          &.select { |file| file.content&.valid_encoding? }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def csproj_file
        @csproj_file ||= T.let(find_and_fetch_with_suffix(".csproj"), T.nilable(T::Array[Dependabot::DependencyFile]))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def vbproj_file
        @vbproj_file ||= T.let(find_and_fetch_with_suffix(".vbproj"), T.nilable(T::Array[Dependabot::DependencyFile]))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def fsproj_file
        @fsproj_file ||= T.let(find_and_fetch_with_suffix(".fsproj"), T.nilable(T::Array[Dependabot::DependencyFile]))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def proj_files
        @proj_files ||= T.let(find_and_fetch_with_suffix(".proj"), T.nilable(T::Array[Dependabot::DependencyFile]))
      end

      sig { params(suffix: String).returns(T::Array[Dependabot::DependencyFile]) }
      def find_and_fetch_with_suffix(suffix)
        repo_contents.select { |f| f.name.end_with?(suffix) }.map { |f| fetch_file_from_host(f.name) }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def nuget_config_files
        return @nuget_config_files if @nuget_config_files

        @nuget_config_files = [*project_files.map do |f|
                                 named_file_up_tree_from_project_file(f, "nuget.config")
                               end].compact.uniq
        @nuget_config_files
      end

      sig do
        params(
          project_file: Dependabot::DependencyFile,
          expected_file_name: String
        )
          .returns(T.nilable(Dependabot::DependencyFile))
      end
      def named_file_up_tree_from_project_file(project_file, expected_file_name)
        found_expected_file = T.let(nil, T.nilable(Dependabot::DependencyFile))
        directory_path = Pathname.new(directory)
        full_project_dir = Pathname.new(project_file.directory).join(project_file.name).dirname
        full_project_dir.ascend.each do |base|
          break if found_expected_file

          candidate_file_path = Pathname.new(base).join(expected_file_name).cleanpath.to_path
          candidate_directory = Pathname.new(File.dirname(candidate_file_path))
          relative_candidate_directory = candidate_directory.relative_path_from(directory_path)
          candidate_file = repo_contents(dir: relative_candidate_directory).find do |f|
            f.name.casecmp?(expected_file_name)
          end
          if candidate_file
            found_expected_file = fetch_file_from_host(File.join(relative_candidate_directory,
                                                                 candidate_file.name))
          end
        end

        found_expected_file
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def global_json
        @global_json ||= T.let(fetch_file_if_present("global.json"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def dotnet_tools_json
        @dotnet_tools_json ||= T.let(fetch_file_if_present(".config/dotnet-tools.json"),
                                     T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def packages_props
        @packages_props ||= T.let(fetch_file_if_present("Packages.props"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def imported_property_files
        imported_property_files = T.let([], T::Array[Dependabot::DependencyFile])

        files = [*project_files, *directory_build_files]

        files.each do |proj_file|
          previously_fetched_files = project_files + imported_property_files
          imported_property_files +=
            fetch_imported_property_files(
              file: proj_file,
              previously_fetched_files: previously_fetched_files
            )
        end

        imported_property_files
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          previously_fetched_files: T::Array[Dependabot::DependencyFile]
        )
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def fetch_imported_property_files(file:, previously_fetched_files:)
        file_id = file.directory + "/" + file.name
        if @fetched_files[file_id]
          T.must(@fetched_files[file_id])
        else
          paths =
            ImportPathsFinder.new(project_file: file).import_paths +
            ImportPathsFinder.new(project_file: file).project_reference_paths +
            ImportPathsFinder.new(project_file: file).project_file_paths

          paths.filter_map do |path|
            next if previously_fetched_files.map(&:name).include?(path)
            next if file.name == path
            next if path.include?("$(")

            fetched_file = fetch_file_from_host(path)
            grandchild_property_files = fetch_imported_property_files(
              file: fetched_file,
              previously_fetched_files: previously_fetched_files + [file]
            )
            @fetched_files[file_id] = [fetched_file, *grandchild_property_files]
            @fetched_files[file_id]
          rescue Dependabot::DependencyFileNotFound
            # Don't worry about missing files too much for now (at least
            # until we start resolving properties)
            nil
          end.flatten
        end
      end
    end
  end
end

Dependabot::FileFetchers.register("nuget", Dependabot::Nuget::FileFetcher)
