# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/version"

module Dependabot
  module Conda
    # Conda version handling delegates to Python version since conda primarily manages Python packages
    class Version < Dependabot::Python::Version
      extend T::Sig

      # Conda supports the same version formats as Python packages from PyPI
      # This includes standard semver, epochs, pre-releases, dev releases, etc.
      sig { override.params(version: VersionParameter).returns(Dependabot::Conda::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Conda::Version)
      end
    end
  end
end

Dependabot::Utils.register_version_class("conda", Dependabot::Conda::Version)
