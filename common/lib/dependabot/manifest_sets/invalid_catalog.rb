# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module ManifestSets
    # Raised when catalog data fails validation. The whole catalog is rejected; it is never partially loaded.
    class InvalidCatalog < StandardError
      extend T::Sig

      sig { returns(String) }
      attr_reader :code

      sig { params(code: String, message: String).void }
      def initialize(code, message)
        @code = code
        super("#{code}: #{message}")
      end
    end
  end
end
