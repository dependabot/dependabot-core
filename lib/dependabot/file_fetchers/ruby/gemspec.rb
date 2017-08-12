# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Ruby
      class Gemspec < Dependabot::FileFetchers::Base
        def self.required_files
          []
        end

        private

        def extra_files
          [gemspec]
        end

        def gemspec
          gemspec = github_client.contents(
            repo,
            path: Pathname.new(directory).cleanpath.to_path,
            ref: commit
          ).find { |file| file.name.end_with?(".gemspec") }

          raise Dependabot::DependencyFileNotFound, "*.gemspec" unless gemspec

          fetch_file_from_github(gemspec.name)
        end
      end
    end
  end
end
