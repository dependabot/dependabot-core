# frozen_string_literal: true

module Dependabot
  module Utils
    module Ruby
      class Requirement < Gem::Requirement
        # Patches Gem::Requirement to make it accept requirement strings like
        # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
        def initialize(*requirements)
          requirements = requirements.flatten.flat_map do |req_string|
            req_string.split(",")
          end

          super(requirements)
        end
      end
    end
  end
end
