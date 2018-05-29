# frozen_string_literal: true

require "dependabot/file_updaters/elixir/hex"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Elixir
      class Hex
        class MixfileSanitizer
          def initialize(mixfile_content:)
            @mixfile_content = mixfile_content
          end

          def sanitized_content
            mixfile_content.
              gsub(/File\.read!\(.*?\)/, '"0.0.1"').
              gsub(/File\.read\(.*?\)/, '{:ok, "0.0.1"}')
          end

          private

          attr_reader :mixfile_content
        end
      end
    end
  end
end
