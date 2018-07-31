# frozen_string_literal: true

require "dependabot/utils/elm/version"

module Dependabot
  module UpdateCheckers
    module Elm
      module ElmPackage
        class CliParser
          class << self
            INSTALL_DEPENDENCY_REGEX = /([^\s]+\/[^\s]+) (\d+\.\d+\.\d+)/
            UPGRADE_DEPENDENCY_REGEX = /([^\s]+\/[^\s]+) \(\d+\.\d+\.\d+ => (\d+\.\d+\.\d+)\)/
            def decode_install_preview(text)
              installs = text.scan(INSTALL_DEPENDENCY_REGEX).
                map {|name, version| [name, Utils::Elm::Version.new(version) ]}.
                to_h

              upgrades = text.scan(UPGRADE_DEPENDENCY_REGEX).
                map {|name, version| [name, Utils::Elm::Version.new(version) ]}.
                to_h

              installs.merge(upgrades)
            end
          end
        end
      end
    end
  end
end