# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Dotnet
      class Nuget < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.any? { |name| name.match?(%r{^[^/]*\.csproj$}) }
        end

        def self.required_files_message
          "Repo must contain a csproj file."
        end

        private

        def fetch_files
          # This method needs to return all of the files that we need to fetch.
          # That means all the files that:
          # - we may need to read in order to figure out what to update
          # - we may wish to change as part of the update
          #
          # You can use the `fetch_file_from_github` helper to get files as
          # long as you know their name. If you need to dynamically figure out
          # what files to fetch, things get harder (the JS file fetcher is a
          # good example)
          fetched_files = []
          fetched_files << csproj_file
          fetched_files
        end

        def csproj_file
          @csproj_file ||=
            begin
              file = repo_contents.find { |f| f.name.end_with?(".csproj") }
              unless file
                raise(Dependabot::DependencyFileNotFound, "<anything>.csproj")
              end
              fetch_file_from_host(file.name)
            end
        end
      end
    end
  end
end
