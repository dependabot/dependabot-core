# frozen_string_literal: true
require "parseconfig"
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Git
      class Submodules < Dependabot::FileParsers::Base
        def parse
          SharedHelpers.in_a_temporary_directory do
            File.write(".gitmodules", gitmodules_file.content)

            ParseConfig.new(".gitmodules").params.map do |_, params|
              # Branch defaults to master - https://git-scm.com/docs/gitmodules
              branch = params["branch"] || "master"

              Dependency.new(
                name: params["path"],
                version: submodule_sha(params["path"]),
                package_manager: "submodules",
                requirements: [{
                  requirement: { url: params["url"], branch: branch },
                  file: ".gitmodules",
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

        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
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
