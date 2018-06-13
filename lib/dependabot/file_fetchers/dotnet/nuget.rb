# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Dotnet
      class Nuget < Dependabot::FileFetchers::Base
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
      end
    end
  end
end
