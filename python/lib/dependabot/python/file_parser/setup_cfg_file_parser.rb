# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"
require "dependabot/python/file_parser/setup_file_parser"

module Dependabot
  module Python
    class FileParser
      class SetupCfgFileParser < Dependabot::Python::FileParser::SetupFileParser
        private

        def parsed_setup_file
          requirements = SharedHelpers.run_helper_subprocess(
            command: "pyenv exec python #{NativeHelpers.python_helper_path}",
            function: "parse_setup_cfg",
            args: [Dir.pwd]
          )

          check_requirements(requirements)
          requirements
        end
      end
    end
  end
end
