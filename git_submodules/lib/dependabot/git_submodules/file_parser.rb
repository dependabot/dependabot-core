# frozen_string_literal: true

require "parseconfig"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"

module Dependabot
  module GitSubmodules
    class FileParser < Dependabot::FileParsers::Base
      def parse
        Dependabot::SharedHelpers.in_a_temporary_directory do
          File.write(".gitmodules", gitmodules_file.content)

          ParseConfig.new(".gitmodules").params.map do |_, params|
            raise DependencyFileNotParseable, gitmodules_file.path if params.fetch("path").end_with?("/")

            Dependency.new(
              name: params.fetch("path"),
              version: submodule_sha(params.fetch("path")),
              package_manager: "submodules",
              requirements: [{
                requirement: nil,
                file: ".gitmodules",
                source: {
                  type: "git",
                  url: absolute_url(params["url"]),
                  branch: params["branch"],
                  ref: params["branch"]
                },
                groups: []
              }]
            )
          end
        end
      end

      private

      def absolute_url(url)
        # Submodules can be specified with a relative URL (e.g., ../repo.git)
        # which we want to expand out into a full URL if present.
        return url unless url.start_with?("../", "./")

        path = Pathname.new(File.join(source.repo, url))
        "https://#{source.hostname}/#{path.cleanpath}"
      end

      def submodule_sha(path)
        submodule = dependency_files.find { |f| f.name == path }
        raise "Submodule not found #{path}" unless submodule

        submodule.content
      end

      def gitmodules_file
        @gitmodules_file ||= get_original_file(".gitmodules")
      end

      def check_required_files
        %w(.gitmodules).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end
    end
  end
end

Dependabot::FileParsers.
  register("submodules", Dependabot::GitSubmodules::FileParser)
