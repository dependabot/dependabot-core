# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/maven/version"
require "dependabot/utils"

module Dependabot
  module Sbt
    # SBT resolves artifacts from Maven repositories and uses the same
    # version ordering specification as Maven.
    class Version < Dependabot::Maven::Version
      extend T::Sig
    end
  end
end

Dependabot::Utils.register_version_class("sbt", Dependabot::Sbt::Version)
