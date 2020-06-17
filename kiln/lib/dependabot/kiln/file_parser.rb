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
        dependency_set += kilnfile_dependencies
        # dependency_set += kilnlock_dependencies
        dependency_set.dependencies
      end

      private

      def check_required_files
        return
      end

      def kilnlock_dependencies


      end

      def kilnfile_dependencies
        dependencies = DependencySet.new

        kilnfile ||= get_original_file("Kilnfile")
        kilnfile_content = YAML.load(kilnfile.content)["releases"][0]

        dependencies << Dependency.new(
            name: kilnfile_content["name"],
                    requirements: [{
                               requirement: kilnfile_content["version"],
                               file: "Kilnfile",
                               groups: [:default],
                               source: {
                                   type: "bosh.io"
                               },
                           }],
            package_manager: "kiln"
        )
        dependencies
      end

    end
  end
end

Dependabot::FileParsers.register("kiln", Dependabot::Kiln::FileParser)
