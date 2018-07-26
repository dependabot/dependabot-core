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
                map {|name, version| [name, version.split('.').map(&:to_i) ]}.
                to_h

              upgrades = text.scan(UPGRADE_DEPENDENCY_REGEX).
                map {|name, version| [name, version.split('.').map(&:to_i) ]}.
                to_h

              installs.merge(upgrades)
            end
          end
        end
      end
    end
  end
end