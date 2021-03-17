# frozen_string_literal: true

require "dependabot/notifications"

module Dependabot
  module FileParsers
    class Base
      attr_reader :dependency_files, :repo_contents_path, :credentials, :source, :options

      def initialize(dependency_files:, repo_contents_path: nil, source:,
                     credentials: [], reject_external_code: false, options: {})
        @dependency_files = dependency_files
        @repo_contents_path = repo_contents_path
        @credentials = credentials
        @source = source
        @reject_external_code = reject_external_code
        @options = options

        check_required_files
      end

      def parse
        raise NotImplementedError
      end

      private

      def check_required_files
        raise NotImplementedError
      end

      def get_original_file(filename)
        dependency_files.find { |f| f.name == filename }
      end
    end
  end
end
