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

        FILE_READ      = /File.read\(.*?\)/
        FILE_READ_BANG = /File.read!\(.*?\)/
        PIPE           = Regexp.escape("|>").freeze
        VERSION_FILE   = /"VERSION"/i

        NESTED_VERSION_FILE_READ = /String\.trim\(#{FILE_READ}\)/
        NESTED_VERSION_FILE_READ_BANG = /String\.trim\(#{FILE_READ_BANG}\)/
        PIPED_VERSION_FILE_READ = /#{VERSION_FILE}[[:space:]]+#{PIPE}[[:space:]]+#{FILE_READ}/
        PIPED_VERSION_FILE_READ_BANG = /#{VERSION_FILE}[[:space:]]+#{PIPE}[[:space:]]+#{FILE_READ_BANG}/

        # rubocop:disable Performance/MethodObjectAsBlock
        def sanitized_content
          mixfile_content.
            then(&method(:prevent_version_file_loading)).
            then(&method(:prevent_config_path_loading))
        end
        # rubocop:enable Performance/MethodObjectAsBlock

        private

        attr_reader :mixfile_content

        def prevent_version_file_loading(configuration)
          configuration.
            gsub(NESTED_VERSION_FILE_READ_BANG, 'String.trim("0.0.1")').
            gsub(NESTED_VERSION_FILE_READ, 'String.trim({:ok, "0.0.1"})').
            gsub(PIPED_VERSION_FILE_READ, '{:ok, "0.0.1"}').
            gsub(PIPED_VERSION_FILE_READ_BANG, '"0.0.1"')
        end

        def prevent_config_path_loading(configuration)
          configuration.
            gsub(/^\s*config_path:.*(?:,|$)/, "")
        end
      end
    end
  end
end
