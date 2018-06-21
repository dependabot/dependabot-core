# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Dotnet
      class Nuget < Dependabot::FileFetchers::Base
        require "dependabot/file_fetchers/dotnet/nuget/import_paths_finder"
        require "dependabot/file_fetchers/dotnet/nuget/sln_project_paths_finder"

        def self.required_files_in?(filenames)
          return true if filenames.any? { |f| f.match?(/^packages\.config$/i) }
          return true if filenames.any? { |f| f.end_with?(".sln") }
          filenames.any? { |name| name.match?(%r{^[^/]*\.(cs|vb|fs)proj$}) }
        end

        def self.required_files_message
          "Repo must contain a csproj file or a packages.config."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files += project_files
          fetched_files += imported_property_files

          fetched_files << packages_config if packages_config
          fetched_files << nuget_config if nuget_config

          return fetched_files unless project_files.none? && !packages_config
          raise(Dependabot::DependencyFileNotFound, "<anything>.csproj")
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
        end

        def packages_config
          @packages_config ||=
            begin
              file = repo_contents.
                     find { |f| f.name.casecmp("packages.config").zero? }
              fetch_file_from_host(file.name) if file
            end
        end

        def sln_file
          @sln_file ||=
            begin
              file = repo_contents.find { |f| f.name.end_with?(".sln") }
              fetch_file_from_host(file.name) if file
            end
        end

        def sln_project_files
          return [] unless sln_file
          @sln_project_files ||=
            begin
              paths = SlnProjectPathsFinder.
                      new(sln_file: sln_file).
                      project_paths
              paths.map { |path| fetch_file_from_host(path) }
            end
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
              fetch_file_from_host(file.name) if file
            end
        end

        def imported_property_files
          previously_fetched_files = project_files
          project_files.flat_map do |proj_file|
            fetch_imported_property_files(
              file: proj_file,
              previously_fetched_files: previously_fetched_files
            )
          end.compact
        end

        def fetch_imported_property_files(file:, previously_fetched_files:)
          paths = ImportPathsFinder.new(project_file: file).import_paths

          paths.flat_map do |path|
            next if previously_fetched_files.map(&:name).include?(path)
            next if file.name == path

            fetched_file = fetch_file_from_host(path, type: "project_import")
            grandchild_gemfiles = fetch_imported_property_files(
              file: fetched_file,
              previously_fetched_files: previously_fetched_files + [file]
            )
            [fetched_file, *grandchild_gemfiles]
          rescue Dependabot::DependencyFileNotFound
            # Don't worry about missing files too much for now (at least
            # until we start resolving properties)
            nil
          end.compact
        end
      end
    end
  end
end
