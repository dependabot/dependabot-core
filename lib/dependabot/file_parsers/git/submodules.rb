# frozen_string_literal: true

require "parseconfig"
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Git
      class Submodules < Dependabot::FileParsers::Base
        GROUP_NAME_REGEX = /^submodule "(?<name>.*)"$/
        def parse
          SharedHelpers.in_a_temporary_directory do
            File.write(".gitmodules", gitmodules_file.content)

            ParseConfig.new(".gitmodules").params.map do |group_name, params|
              # Branch defaults to master - https://git-scm.com/docs/gitmodules
              branch = params["branch"] || "master"

              submodule_name =
                group_name.match(GROUP_NAME_REGEX).named_captures.fetch("name")

              Dependency.new(
                name: submodule_name,
                version: submodule_sha(params["path"]),
                package_manager: "submodules",
                requirements: [{
                  requirement: nil,
                  file: ".gitmodules",
                  source: {
                    type: "git",
                    url: params["url"],
                    branch: branch,
                    ref: branch
                  },
                  groups: []
                }]
              )
            end
          end
        end

        private

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
end
