# frozen_string_literal: true

module Dependabot
  module FileUpdaters
    class Base
      attr_reader :dependencies, :dependency_files, :credentials

      def self.updated_files_regex
        raise NotImplementedError
      end

      def initialize(dependencies:, dependency_files:, credentials:)
        @dependencies = dependencies
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

      def file_changed?(file)
        dependencies.any? { |dep| requirement_changed?(file, dep) }
      end

      def requirement_changed?(file, dependency)
        changed_requirements =
          dependency.requirements - dependency.previous_requirements

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
