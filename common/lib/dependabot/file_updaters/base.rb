# frozen_string_literal: true

module Dependabot
  module FileUpdaters
    class Base
<<<<<<< HEAD
      attr_reader :dependencies, :dependency_files, :repo_contents_path,
                  :credentials
=======
      attr_reader :dependencies, :dependency_files, :repo_path, :credentials
>>>>>>> Add cloned repo to updater checker and file updater

      def self.updated_files_regex
        raise NotImplementedError
      end

<<<<<<< HEAD
      def initialize(dependencies:, dependency_files:, repo_contents_path: nil,
                     credentials:)
        @dependencies = dependencies
        @dependency_files = dependency_files
        @repo_contents_path = repo_contents_path
=======
      def initialize(dependencies:, dependency_files:, repo_path: nil,
                     credentials:)
        @dependencies = dependencies
        @dependency_files = dependency_files
        @repo_path = repo_path
>>>>>>> Add cloned repo to updater checker and file updater
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
