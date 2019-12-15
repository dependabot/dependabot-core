# frozen_string_literal: true

require "dependabot/sbt/file_parser"

module Dependabot
  module Sbt
    class FileParser
      class RepositoriesFinder
        CENTRAL_REPO_URL = "https://repo.maven.apache.org/maven2"

        def initialize(dependency_files:, target_dependency_file:)
          @dependency_files = dependency_files
          @target_dependency_file = target_dependency_file
          raise "No target file!" unless target_dependency_file
        end

        def repository_urls
          [CENTRAL_REPO_URL]
        end
      end
    end
  end
end
