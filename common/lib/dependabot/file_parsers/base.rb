# frozen_string_literal: true

module Dependabot
  module FileParsers
    class Base
      attr_reader :dependency_files, :repo_contents_path, :credentials, :source

      def initialize(dependency_files:, repo_contents_path: nil, source:,
                     credentials: [])
        @dependency_files = dependency_files
        @repo_contents_path = repo_contents_path
        @credentials = credentials
        @source = source

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
