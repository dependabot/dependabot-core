# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/maven/version"
require "dependabot/utils"

module Dependabot
  module Clojure
    # Clojure dependencies are Maven artifacts, so they follow Maven's version ordering.
    class Version < Dependabot::Maven::Version
      extend T::Sig

      VERSION_PATTERN = T.let(Dependabot::Maven::Version::VERSION_PATTERN, String)
    end
  end
end

Dependabot::Utils.register_version_class("clojure", Dependabot::Clojure::Version)
