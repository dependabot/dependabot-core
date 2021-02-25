# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/haskell/version"

module Dependabot
  module Haskell
    # Lifted from the bundler package manager
    class Requirement < Gem::Requirement

      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string.
            # cabal uses ==, ruby =
            gsub("==", "=").
            gsub(/[\(\)]/, "").
            # Patches Gem::Requirement to make it accept requirement strings like
            # ">= 4.2.5.1 && < 4.2.6" without first needing to split them.
            split("&&").flat_map do |req_str|
              # cabal does || too...
              req_str.split("||").
              map do |req_str|
                req_str.
                  # take out wildcards as Gem::Requirement doesn't get them
                  gsub(".*", "")
              end
            end
          end

        super(requirements)
      end

      # For consistency with other languages, we define a requirements array.
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

    end
  end
end

Dependabot::Utils.register_requirement_class(
  "haskell",
  Dependabot::Haskell::Requirement
)
