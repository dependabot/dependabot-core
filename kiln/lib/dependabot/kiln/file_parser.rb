require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "yaml"
require "dependabot/file_parsers/base/dependency_set"

module Dependabot
  module Kiln
    class FileParser < Dependabot::FileParsers::Base
      VALID_SOURCES = ["bosh.io", "compiled-releases", "final-pcf-bosh-releases"]

      def parse
        dependency_set = DependencySet.new
        dependency_set += kiln_dependencies
        dependency_set.dependencies
      end

      private

      def check_required_files
        raise "No Kilnfile!" unless kilnfile
        raise "No Kilnfile.lock!" unless kilnlockfile
      end

      def kilnfile
        @kilnfile ||= get_original_file("Kilnfile")
      end

      def kilnlockfile
        @kilnlockfile ||= get_original_file("Kilnfile.lock")
      end

      def kiln_dependencies
        dependencies = DependencySet.new


        kilnfile ||= get_original_file("Kilnfile")
        kilnlockfile ||= get_original_file("Kilnfile.lock")

        kilnfile_contents = YAML.load(kilnfile.content)["releases"]
        kilnlockfile_contents = YAML.load(kilnlockfile.content)["releases"]

        if (kilnfile_contents.length != kilnlockfile_contents.length)
          raise "Number of releases in Kilnfile and Kilnfile.lock does not match"
        end

        kilnfile_contents.each_with_index do |kilnfile_content, index|

          validate_source(kilnfile_content)

          dependencies << Dependency.new(
              name: kilnfile_content["name"],
              requirements: [{
                                 requirement: kilnfile_content["version"],
                                 file: kilnfile.name,
                                 groups: [:default],
                                 source: {
                                     type: kilnfile_content["source"],
                                     remote_path: kilnlockfile_contents.find { |release| release["name"] == kilnfile_content["name"] }["remote_path"],
                                     sha: kilnlockfile_contents.find { |release| release["name"] == kilnfile_content["name"] }["sha1"],
                                 },
                             }],
              version: kilnlockfile_contents.find { |release| release["name"] == kilnfile_content["name"] }["version"],
              package_manager: "kiln"
          )
        end
        dependencies
      end

      def validate_source(release)
        if (!VALID_SOURCES.include? release["source"])
          raise "The release source '#{release["source"]}' is invalid, source must be one of: #{Dependabot::Kiln::FileParser::VALID_SOURCES.join(', ')}"
        end
      end
    end
  end
end
Dependabot::FileParsers.register("kiln", Dependabot::Kiln::FileParser)
