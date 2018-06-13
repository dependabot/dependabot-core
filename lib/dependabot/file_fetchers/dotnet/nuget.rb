# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Dotnet
      class Nuget < Dependabot::FileFetchers::Base
        require "dependabot/file_fetchers/dotnet/nuget/import_paths_finder"

        def self.required_files_in?(filenames)
          filenames.any? { |name| name.match?(%r{^[^/]*\.(cs|vb|fs)proj$}) }
        end

        def self.required_files_message
          "Repo must contain a csproj file."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << csproj_file if csproj_file
          fetched_files << vbproj_file if vbproj_file
          fetched_files << fsproj_file if fsproj_file

          fetched_files += imported_property_files(fetched_files)

          return fetched_files unless fetched_files.none?
          raise(Dependabot::DependencyFileNotFound, "<anything>.csproj")
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

        def imported_property_files(project_files)
          previously_fetched_files = []
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

            fetched_file = fetch_file_from_host(path)
            grandchild_gemfiles = fetch_imported_property_files(
              file: fetched_file,
              previously_fetched_files: previously_fetched_files + [file]
            )
            [fetched_file, *grandchild_gemfiles]
          end.compact
        end
      end
    end
  end
end
