# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/lein/native_helpers"

module Dependabot
  module Lein
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [/^project\.clj$/]
      end

      def updated_dependency_files
        file = dependency_files.find { |f| f.name == "project.clj" }

        dependencies_for_args = dependencies.map do |dependency|
          {
            dependency: dependency.name.gsub(":", "/"),
            version: dependency.version,
            previous: dependency.previous_version
          }
        end

        result = SharedHelpers.run_helper_subprocess(
          command: NativeHelpers.helper_path,
          function: "update_dependencies",
          args: {
            file: file.content,
            dependencies: dependencies_for_args
          }
        )

        [updated_file(file: file, content: result)]
      end

      private

      def check_required_files
        raise "No project.clj!" unless get_original_file("project.clj")
      end
    end
  end
end

Dependabot::FileUpdaters.register("lein", Dependabot::Lein::FileUpdater)
