# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/shared_helpers"

module Dependabot
  module Lein
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.include?('project.clj')
      end

      def self.required_files_message
        "Repo must contain a project.clj."
      end

      private

      def fetch_files
        [project, pom]
      end

      def project
        @project ||= fetch_file_from_host("project.clj")
      end

      def pom
        @pom ||= generate_pom(project)
      end

      def generate_pom(project)
        # TODO install helpers properly onto path
        result = SharedHelpers.run_helper_subprocess(
          command: "cd lein/helpers; /usr/local/lein/bin/lein run",
          function: "generate_pom",
          args: project.content,
          escape_command_str: false
        )

        Dependabot::DependencyFile.new(
          name: "pom.xml",
          content: result
        )
      end
    end
  end
end

Dependabot::FileFetchers.register("lein", Dependabot::Lein::FileFetcher)
