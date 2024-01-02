# typed: false
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
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

      def self.required_files_in?(filenames)
        return true if filenames.any? { |f| f.match?(/^packages\.config$/i) }
        return true if filenames.any? { |f| f.end_with?(".sln") }
        return true if filenames.any? { |f| f.match?("^src$") }
        return true if filenames.any? { |f| f.end_with?(".proj") }

        filenames.any? { |name| name.match?(%r{^[^/]*\.[a-z]{2}proj$}) }
      end

      def self.required_files_message
        "Repo must contain a .proj file, .(cs|vb|fs)proj file, or a packages.config."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        @files_fetched = {}
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
          raise @missing_sln_project_file_errors.first if @missing_sln_project_file_errors&.any?

          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "<anything>.(cs|vb|fs)proj")
          )
        end

        fetched_files
      end

      private

      def project_files
        @project_files ||=
          begin
            project_files = []
            project_files += csproj_file
            project_files += vbproj_file
            project_files += fsproj_file
            project_files += sln_project_files
            project_files += proj_files
            project_files += project_files.filter_map { |f| directory_packages_props_file_from_project_file(f) }
            project_files
          end
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        raise(
          Dependabot::DependencyFileNotFound,
          File.join(directory, "<anything>.(cs|vb|fs)proj")
        )
      end

      def packages_config_files
        return @packages_config_files if @packages_config_files

        candidate_paths =
          [*project_files.map { |f| File.dirname(f.name) }, "."].uniq

        @packages_config_files ||=
          candidate_paths.filter_map do |dir|
            file = repo_contents(dir: dir)
                   .find { |f| f.name.casecmp("packages.config").zero? }
            fetch_file_from_host(File.join(dir, file.name)) if file
          end
      end

      # rubocop:disable Metrics/PerceivedComplexity
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

      def directory_build_files
        @directory_build_files ||= fetch_directory_build_files
      end

      def fetch_directory_build_files
        attempted_dirs = []
        directory_build_files = []
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

      def sln_project_files
        return [] unless sln_files

        @sln_project_files ||=
          begin
            paths = sln_files.flat_map do |sln_file|
              SlnProjectPathsFinder
                .new(sln_file: sln_file)
                .project_paths
            end

            paths.filter_map do |path|
              fetch_file_from_host(path)
            rescue Dependabot::DependencyFileNotFound => e
              @missing_sln_project_file_errors ||= []
              @missing_sln_project_file_errors << e
              # Don't worry about missing files too much for now (at least
              # until we start resolving properties)
              nil
            end
          end
      end

      def sln_files
        return unless sln_file_names

        @sln_files ||=
          sln_file_names
          .map { |sln_file_name| fetch_file_from_host(sln_file_name) }
          .select { |file| file.content.valid_encoding? }
      end

      def csproj_file
        @csproj_file ||= find_and_fetch_with_suffix(".csproj")
      end

      def vbproj_file
        @vbproj_file ||= find_and_fetch_with_suffix(".vbproj")
      end

      def fsproj_file
        @fsproj_file ||= find_and_fetch_with_suffix(".fsproj")
      end

      def proj_files
        @proj_files ||= find_and_fetch_with_suffix(".proj")
      end

      def directory_packages_props_file_from_project_file(project_file)
        # walk up the tree from each project file stopping at the first `Directory.Packages.props` file found
        # https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management#central-package-management-rules

        found_directory_packages_props_file = nil
        directory_path = Pathname.new(directory)
        full_project_dir = Pathname.new(project_file.directory).join(project_file.name).dirname
        full_project_dir.ascend.each do |base|
          break if found_directory_packages_props_file

          candidate_file_path = Pathname.new(base).join("Directory.Packages.props").cleanpath.to_path
          candidate_directory = Pathname.new(File.dirname(candidate_file_path))
          relative_candidate_directory = candidate_directory.relative_path_from(directory_path)
          candidate_file = repo_contents(dir: relative_candidate_directory).find do |f|
            f.name.casecmp?("Directory.Packages.props")
          end
          found_directory_packages_props_file = fetch_file_from_host(candidate_file.name) if candidate_file
        end

        found_directory_packages_props_file
      end

      def find_and_fetch_with_suffix(suffix)
        repo_contents.select { |f| f.name.end_with?(suffix) }.map { |f| fetch_file_from_host(f.name) }
      end

      def nuget_config_files
        return @nuget_config_files if @nuget_config_files

        @nuget_config_files = []
        candidate_paths = [*project_files.map { |f| File.dirname(f.name) }, "."].uniq
        visited_directories = Set.new
        candidate_paths.each do |dir|
          search_in_directory_and_parents(dir, visited_directories)
        end
        @nuget_config_files
      end

      def search_in_directory_and_parents(dir, visited_directories)
        loop do
          break if visited_directories.include?(dir)

          visited_directories << dir
          file = repo_contents(dir: dir)
                 .find { |f| f.name.casecmp("nuget.config").zero? }
          if file
            file = fetch_file_from_host(File.join(dir, file.name))
            file&.tap { |f| f.support_file = true }
            @nuget_config_files << file
          end
          dir = File.dirname(dir)
        end
      end

      def global_json
        return @global_json if defined?(@global_json)

        @global_json = fetch_file_if_present("global.json")
      end

      def dotnet_tools_json
        return @dotnet_tools_json if defined?(@dotnet_tools_json)

        @dotnet_tools_json = fetch_file_if_present(".config/dotnet-tools.json")
      end

      def packages_props
        return @packages_props if defined?(@packages_props)

        @packages_props = fetch_file_if_present("Packages.props")
      end

      def imported_property_files
        imported_property_files = []

        files = [*project_files, *directory_build_files]

        files.each do |proj_file|
          previously_fetched_files = project_files + imported_property_files
          fetched_property_files = fetch_imported_property_files(
            file: proj_file,
            previously_fetched_files: previously_fetched_files
          )
          imported_property_files += fetched_property_files
        end

        imported_property_files
      end

      def fetch_imported_property_files(file:, previously_fetched_files:)
        file_id = file.directory + "/" + file.name
        unless @files_fetched[file_id]
          paths =
            ImportPathsFinder.new(project_file: file).import_paths +
            ImportPathsFinder.new(project_file: file).project_reference_paths +
            ImportPathsFinder.new(project_file: file).project_file_paths

          paths.flat_map do |path|
            next if previously_fetched_files.map(&:name).include?(path)
            next if file.name == path
            next if path.include?("$(")

            fetched_file = fetch_file_from_host(path)
            grandchild_property_files = fetch_imported_property_files(
              file: fetched_file,
              previously_fetched_files: previously_fetched_files + [file]
            )
            result = [fetched_file, *grandchild_property_files]
            @files_fetched[file_id] = result
            result
          rescue Dependabot::DependencyFileNotFound
            # Don't worry about missing files too much for now (at least
            # until we start resolving properties)
            nil
          end.compact
        end
        @files_fetched[file_id]
      end
    end
  end
end

Dependabot::FileFetchers.register("nuget", Dependabot::Nuget::FileFetcher)
