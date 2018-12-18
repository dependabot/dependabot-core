# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Nuget
    class FileFetcher < Dependabot::FileFetchers::Base
      require_relative "file_fetcher/import_paths_finder"
      require_relative "file_fetcher/sln_project_paths_finder"

      def self.required_files_in?(filenames)
        return true if filenames.any? { |f| f.match?(/^packages\.config$/i) }
        return true if filenames.any? { |f| f.end_with?(".sln") }

        filenames.any? { |name| name.match?(%r{^[^/]*\.[a-z]{2}proj$}) }
      end

      def self.required_files_message
        "Repo must contain a .(cs|vb|fs)proj file or a packages.config."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += project_files
        fetched_files += directory_build_props_files
        fetched_files += imported_property_files

        fetched_files += packages_config_files
        fetched_files << nuget_config if nuget_config

        fetched_files = fetched_files.uniq

        if project_files.none? && packages_config_files.none?
          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "<anything>.(cs|vb|fs)proj")
          )
        end

        fetched_files
      end

      def project_files
        @project_files ||=
          begin
            project_files = []
            project_files << csproj_file if csproj_file
            project_files << vbproj_file if vbproj_file
            project_files << fsproj_file if fsproj_file

            project_files += sln_project_files
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
          candidate_paths.map do |dir|
            file = repo_contents(dir: dir).
                   find { |f| f.name.casecmp("packages.config").zero? }
            fetch_file_from_host(File.join(dir, file.name)) if file
          end.compact
      end

      def sln_file_name
        sln_files = repo_contents.select { |f| f.name.end_with?(".sln") }
        src_dir = repo_contents.any? { |f| f.name == "src" && f.type == "dir" }

        # If there are no sln files but there is a src directory, check that dir
        if sln_files.none? && src_dir
          sln_files = repo_contents(dir: "src").
                      select { |f| f.name.end_with?(".sln") }.
                      map { |file| file.dup }.
                      map { |file| file.tap { |f| f.name = "src/" + f.name } }
        end

        # Return `nil` if no sln files were found
        return if sln_files.none?

        # Use the biggest sln file
        sln_files.max_by(&:size).name
      end

      def directory_build_props_files
        return @directory_build_props_files if @directory_build_checked

        @directory_build_checked = true
        attempted_paths = []
        @directory_build_props_files = []

        # Don't need to insert "." here, because Directory.Build.props files
        # can only be used by project files (not packages.config ones)
        project_files.map { |f| File.dirname(f.name) }.uniq.map do |dir|
          possible_paths = dir.split("/").map.with_index do |_, i|
            base = dir.split("/").first(i + 1).join("/")
            Pathname.new(base + "/Directory.Build.props").cleanpath.to_path
          end.reverse + ["Directory.Build.props"]

          possible_paths.each do |path|
            break if attempted_paths.include?(path)

            attempted_paths << path
            @directory_build_props_files << fetch_file_from_host(path)
          rescue Dependabot::DependencyFileNotFound
            next
          end
        end

        @directory_build_props_files
      end

      def sln_project_files
        return [] unless sln_file

        @sln_project_files ||=
          begin
            paths = SlnProjectPathsFinder.
                    new(sln_file: sln_file).
                    project_paths

            paths.map do |path|
              fetch_file_from_host(path)
            rescue Dependabot::DependencyFileNotFound
              # Don't worry about missing files too much for now (at least
              # until we start resolving properties)
              nil
            end.compact
          end
      end

      def sln_file
        return unless sln_file_name

        @sln_file ||= fetch_file_from_host(sln_file_name)
      end

      def csproj_file
        @csproj_file ||=
          begin
            file = repo_contents.find { |f| f.name.end_with?(".csproj") }
            fetch_file_from_host(file.name) if file
          end
      end

      def vbproj_file
        @vbproj_file ||=
          begin
            file = repo_contents.find { |f| f.name.end_with?(".vbproj") }
            fetch_file_from_host(file.name) if file
          end
      end

      def fsproj_file
        @fsproj_file ||=
          begin
            file = repo_contents.find { |f| f.name.end_with?(".fsproj") }
            fetch_file_from_host(file.name) if file
          end
      end

      def nuget_config
        @nuget_config ||=
          begin
            file = repo_contents.
                   find { |f| f.name.casecmp("nuget.config").zero? }
            file = fetch_file_from_host(file.name) if file
            file&.tap { |f| f.support_file = true }
          end
      end

      def imported_property_files
        imported_property_files = []

        [*project_files, *directory_build_props_files].each do |proj_file|
          previously_fetched_files = project_files + imported_property_files
          imported_property_files +=
            fetch_imported_property_files(
              file: proj_file,
              previously_fetched_files: previously_fetched_files
            )
        end

        imported_property_files
      end

      def fetch_imported_property_files(file:, previously_fetched_files:)
        paths =
          ImportPathsFinder.new(project_file: file).import_paths +
          ImportPathsFinder.new(project_file: file).project_reference_paths

        paths.flat_map do |path|
          next if previously_fetched_files.map(&:name).include?(path)
          next if file.name == path
          next if path.include?("$(")

          fetched_file = fetch_file_from_host(path)
          grandchild_property_files = fetch_imported_property_files(
            file: fetched_file,
            previously_fetched_files: previously_fetched_files + [file]
          )
          [fetched_file, *grandchild_property_files]
        rescue Dependabot::DependencyFileNotFound
          # Don't worry about missing files too much for now (at least
          # until we start resolving properties)
          nil
        end.compact
      end
    end
  end
end

Dependabot::FileFetchers.register("nuget", Dependabot::Nuget::FileFetcher)
