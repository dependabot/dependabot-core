# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/clojure/version"

module Dependabot
  module Clojure
    LANGUAGE = "clojure"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      # The version comes from the org.clojure/clojure dependency, when declared.
      sig { params(raw_version: T.nilable(String)).void }
      def initialize(raw_version)
        super(
          name: LANGUAGE,
          version: raw_version ? Version.new(raw_version) : nil
        )
      end
    end
  end
end
