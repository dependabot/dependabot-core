# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Conda
    class NameNormaliser
      extend T::Sig

      sig { params(name: String).returns(String) }
      def self.normalise(name)
        # Conda package names follow similar rules to Python packages
        # Convert to lowercase and replace underscores/dots with hyphens
        name.downcase.tr("_.", "-")
      end
    end
  end
end
