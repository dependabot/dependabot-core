# frozen_string_literal: true

require "dependabot/elm/version"
require "dependabot/elm/update_checker"

module Dependabot
  module Elm
    class UpdateChecker
      class CliParser
        INSTALL_DEPENDENCY_REGEX = %r{([^\s]+\/[^\s]+)\s+(\d+\.\d+\.\d+)}
        UPGRADE_DEPENDENCY_REGEX = %r{([^\s]+\/[^\s]+) \(\d+\.\d+\.\d+ => (\d+\.\d+\.\d+)\)}

        def self.decode_install_preview(text)
          installs = {}

          # Parse new installs
          text.scan(INSTALL_DEPENDENCY_REGEX).
            each { |n, v| installs[n] = Elm::Version.new(v) }

          # Parse upgrades
          text.scan(UPGRADE_DEPENDENCY_REGEX).
            each { |n, v| installs[n] = Elm::Version.new(v) }

          installs
        end
      end
    end
  end
end
