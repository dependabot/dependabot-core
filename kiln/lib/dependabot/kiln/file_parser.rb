require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "yaml"

module Dependabot
  module Kiln
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      def parse
        dependency_set = DependencySet.new
        dependency_set += kiln_dependencies
        dependency_set.dependencies
      end

      private

      def check_required_files
        return
      end

      def kiln_dependencies
        dependencies = DependencySet.new

        kilnfile ||= get_original_file("Kilnfile")
        kilnlockfile ||= get_original_file("Kilnfile.lock")

        kilnfile_contents = YAML.load(kilnfile.content)["releases"]
        kilnlockfile_contents = YAML.load(kilnlockfile.content)["releases"]

        kilnfile_contents.each_with_index do |kilnfile_content, index|
            dependencies << Dependency.new(
                name: kilnfile_content["name"],
                requirements: [{
                                   requirement: kilnfile_content["version"],
                                   file: kilnfile.name,
                                   groups: [:default],
                                   source: {
                                       type: "bosh.io"
                                   },
                               }],
                version: kilnlockfile_contents[index]["version"],
                package_manager: "kiln"
            )
          end
          dependencies
        end
      end
    end
end
Dependabot::FileParsers.register("kiln", Dependabot::Kiln::FileParser)
