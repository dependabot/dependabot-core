require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Kiln
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      def parse
        dependency_set = DependencySet.new
        dependency_set += kilnfile_dependencies
        dependency_set.dependencies
      end

      private

      def check_required_files
        return
      end

      def kilnfile_dependencies
        dependencies = DependencySet.new

        dependencies << Dependency.new(
          name: "uaa",
          version: "74.16.0",
          requirements: [{
                             requirement: "~> 74.16.0",
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
