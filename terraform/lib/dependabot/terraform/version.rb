# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/version"

# Terraform pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
#
# See, for example, https://releases.hashicorp.com/terraform/

module Dependabot
  module Terraform
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        super
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Terraform::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Terraform::Version)
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("terraform", Dependabot::Terraform::Version)
