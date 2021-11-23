# frozen_string_literal: true

require "dependabot/hex/file_updater"
require "dependabot/shared_helpers"

module Dependabot
  module Hex
    class FileUpdater
      class MixfileSanitizer
        def initialize(mixfile_content:)
          @mixfile_content = mixfile_content
        end

        def sanitized_content
          mixfile_content.
            yield_self(&method(:prevent_version_file_loading)).
            yield_self(&method(:prevent_config_path_loading))
        end

        private

        attr_reader :mixfile_content

        def prevent_version_file_loading(configuration)
          configuration.
            gsub(/String\.trim\(File\.read!\(.*?\)\)/, 'String.trim("0.0.1")').
            gsub(/String\.trim\(File\.read\(.*?\)\)/, 'String.trim({:ok, "0.0.1"})')
        end

        def prevent_config_path_loading(configuration)
          configuration.
            gsub(/^\s*config_path:.*(?:,|$)/, "")
        end
      end
    end
  end
end
