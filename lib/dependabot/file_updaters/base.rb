# frozen_string_literal: true
module Dependabot
  module FileUpdaters
    class Base
      attr_reader :dependency, :dependency_files, :github_access_token

      def self.updated_files_regex
        raise NotImplementedError
      end

      def initialize(dependency:, dependency_files:, github_access_token:)
        @dependency = dependency
        @dependency_files = dependency_files
        @github_access_token = github_access_token

        check_required_files
      end

      def updated_dependency_files
        raise NotImplementedError
      end

      private

      def check_required_files
        required_files.each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end

      def required_files
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
