# frozen_string_literal: true

require_relative "setup_file_parser_base"

module Dependabot
  module Python
    class FileParser
      class SetupCfgFileParser < SetupFileParserBase
        private

        def function
          "parse_setup_cfg"
        end
      end
    end
  end
end
