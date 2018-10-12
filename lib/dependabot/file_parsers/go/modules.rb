# frozen_string_literal: true

require "toml-rb"

require "dependabot/errors"
require "dependabot/dependency"
require "dependabot/shared_helpers"
require "dependabot/source"

require "dependabot/file_parsers/base"
require "dependabot/utils/go/requirement"
require "dependabot/utils/go/path_converter"

module Dependabot
  module FileParsers
    module Go
      class Modules < Dependabot::FileParsers::Base
        require_relative "modules/go_mod_parser"

        def parse
          go_mod_dependencies.dependencies
        end

        private

        def go_mod_dependencies
          @go_mod_dependencies ||=
            Modules::GoModParser.
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
end
