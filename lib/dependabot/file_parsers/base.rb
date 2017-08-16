# frozen_string_literal: true
module Dependabot
  module FileParsers
    class Base
      attr_reader :dependency_files

      def initialize(dependency_files:)
        @dependency_files = dependency_files

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
