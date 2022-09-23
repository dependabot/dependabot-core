# frozen_string_literal: true

module Dependabot
  module FileUpdaters
    class Base
      attr_reader :dependencies, :dependency_files, :repo_contents_path,
                  :credentials, :options

      def self.updated_files_regex
        raise NotImplementedError
      end

      def initialize(dependencies:, dependency_files:, repo_contents_path: nil,
                     credentials:, options: {})
        @dependencies = dependencies
        @dependency_files = dependency_files
        @repo_contents_path = repo_contents_path
        @credentials = credentials
        @options = options

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

      def file_changed?(file)
        dependencies.any? { |dep| requirement_changed?(file, dep) }
      end

      def requirement_changed?(file, dependency)
        changed_requirements =
          dependency.requirements - dependency.previous_requirements |
          dependency.previous_requirements - dependency.requirements

        changed_requirements.any? { |f| f[:file] == file.name }
      end

      def updated_file(file:, content:)
        updated_file = file.dup
        updated_file.content = content
        updated_file
      end
    end
  end
end
