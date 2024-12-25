# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pub/version"
require "dependabot/ecosystem"

module Dependabot
  module Pub
    LANGUAGE = "dart"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(LANGUAGE, nil, Version.new(raw_version))
      end
    end
  end
end
