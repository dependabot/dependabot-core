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
          lockfile_content = kilnlockfile_contents.find { |release| release["name"] == kilnfile_content["name"] }

          if lockfile_content.nil?
            raise "The release '#{kilnfile_content["name"]}' does not match any release in Kilnfile.lock"
          end

          dependencies << Dependency.new(
              name: kilnfile_content["name"],
              requirements: [{
                                 requirement: kilnfile_content["version"],
                                 file: kilnfile.name,
                                 groups: [:default],
                                 source: {
                                     type: lockfile_content["remote_source"],
                                     remote_path: lockfile_content["remote_path"],
                                     sha: lockfile_content["sha1"],
                                 },
                             }],
              version: lockfile_content["version"],
              package_manager: "kiln"
          )
        end
        dependencies
      end
    end
  end
end
Dependabot::FileParsers.register("kiln", Dependabot::Kiln::FileParser)
