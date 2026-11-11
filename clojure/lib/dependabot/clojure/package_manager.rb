# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"

module Dependabot
  module Clojure
    LEIN_PACKAGE_MANAGER = "lein"
    DEPS_PACKAGE_MANAGER = "deps"

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(name: String).void }
      def initialize(name)
        super(name: name)
      end
    end
  end
end
