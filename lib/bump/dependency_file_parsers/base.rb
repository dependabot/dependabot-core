# frozen_string_literal: true
module Bump
  module DependencyFileParsers
    class Base
      attr_reader :dependency_files

      def initialize(dependency_files:)
        @dependency_files = dependency_files

        required_files.each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end

      def parse
        raise NotImplementedError
      end

      private

      def required_files
        raise NotImplementedError
      end

      def get_original_file(filename)
        dependency_files.find { |f| f.name == filename }
      end
    end
  end
end
