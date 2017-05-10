# frozen_string_literal: true
module Bump
  module DependencyFileUpdaters
    class Base
      attr_reader :dependency, :dependency_files, :github_access_token

      def initialize(dependency:, dependency_files:, github_access_token:)
        @dependency = dependency
        @dependency_files = dependency_files
        @github_access_token = github_access_token
      end

      def updated_dependency_files
        raise NotImplementedError
      end

      private

      def get_original_file(filename)
        file = dependency_files.find { |f| f.name == filename }

        raise "No #{filename}!" unless file
        file
      end

      def updated_file(file:, content:)
        updated_file = file.dup
        updated_file.content = content
        updated_file
      end
    end
  end
end
