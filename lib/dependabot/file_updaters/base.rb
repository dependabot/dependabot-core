# frozen_string_literal: true

module Dependabot
  module FileUpdaters
    class Base
      attr_reader :dependency, :dependency_files, :credentials

      def self.updated_files_regex
        raise NotImplementedError
      end

      def initialize(dependency:, dependency_files:, credentials:)
        @dependency = dependency
        @dependency_files = dependency_files
        @credentials = credentials

        check_required_files
      end

      def updated_dependency_files
        raise NotImplementedError
      end

      private

      def check_required_files
        raise NotImplementedError
      end

      def get_original_file(filename)
        dependency_files.find { |f| f.name == filename }
      end

      def updated_file(file:, content:)
        updated_file = file.dup
        updated_file.content = content
        updated_file
      end
    end
  end
end
