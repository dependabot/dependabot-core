# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/lein/native_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Lein
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.include?("project.clj")
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
        result = SharedHelpers.run_helper_subprocess(
          command: NativeHelpers.helper_path,
          function: "generate_pom",
          args: { file: project.content }
        )

        Dependabot::DependencyFile.new(name: "pom.xml", content: result)
      end
    end
  end
end

Dependabot::FileFetchers.register("lein", Dependabot::Lein::FileFetcher)
