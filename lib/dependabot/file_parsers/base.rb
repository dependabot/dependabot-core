# frozen_string_literal: true

module Dependabot
  module FileParsers
    class Base
      attr_reader :dependency_files, :credentials, :repo

      def initialize(dependency_files:, repo:, credentials: [])
        @dependency_files = dependency_files
        @credentials = credentials
        @repo = repo

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
