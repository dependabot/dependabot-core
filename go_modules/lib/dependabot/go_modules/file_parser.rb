# frozen_string_literal: true

require "dependabot/file_parsers/base"

module Dependabot
  module GoModules
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/go/modules/go_mod_parser"

      def parse
        go_mod_dependencies.dependencies
      end

      private

      def go_mod_dependencies
        @go_mod_dependencies ||=
          Dependabot::FileParsers::Go::Modules::GoModParser.
          new(dependency_files: dependency_files, credentials: credentials).
          dependency_set
      end

      def go_mod
        @go_mod ||= get_original_file("go.mod")
      end

      def check_required_files
        raise "No go.mod!" unless go_mod
      end
    end
  end
end
