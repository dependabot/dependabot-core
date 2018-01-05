# frozen_string_literal: true

require "dependabot/update_checkers/java/maven"

# Java versions use dots and dashes when tokenising their versions.
# Gem::Version converts a "-" to ".pre.", so we override the `to_s` method.
#
# See https://maven.apache.org/pom.html#Version_Order_Specification for details.

module Dependabot
  module UpdateCheckers
    module Java
      class Maven
        class Version < Gem::Version
          def initialize(version)
            @version_string = version.to_s
            super
          end

          def to_s
            @version_string
          end

          # TODO: We almost certainly need to override version comparison here
        end
      end
    end
  end
end
