# frozen_string_literal: true

require "dependabot/update_checkers/rust/cargo"

# Rust pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.

module Dependabot
  module UpdateCheckers
    module Rust
      class Cargo
        class Version < Gem::Version
          def initialize(version)
            @version_string = version.to_s
            super
          end

          def to_s
            @version_string
          end
        end
      end
    end
  end
end
