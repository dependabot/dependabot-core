# frozen_string_literal: true

require "dependabot/notifications"

module Dependabot
  module FileParsers
    class Base
      attr_reader :dependency_files, 
                  :repo_contents_path, 
                  :credentials, 
                  :source, 
                  :options

      def initialize(dependency_files:, 
                     repo_contents_path: nil, 
                     source:,
                     credentials: [], 
                     reject_external_code: false, 
                     options: {})
        @dependency_files = dependency_files
        @repo_contents_path = repo_contents_path
        @credentials = credentials
        @source = source
        @reject_external_code = reject_external_code
        @options = options

        check_required_files
      end

      # Returns an array of dependencies for the project. 
      # Each dependency has a name, version and a requirements array.
      def parse
        raise NotImplementedError
      end

      private

      # Raise a runtime error unless an appropriate set of files is provided.
      def check_required_files
        raise NotImplementedError
      end

      def get_original_file(filename)
        dependency_files.find { |f| f.name == filename }
      end
    end
  end
end
