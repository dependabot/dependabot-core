# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Bazel
    class Version < Dependabot::Version
      extend T::Sig

      # Bazel uses semantic versioning with hyphens for pre-release versions (e.g., "1.7.0-rc4")
      # Dependabot::Version normalizes these to dot notation with "pre" prefix (e.g., "1.7.0.pre.rc4")
      # We need to preserve the original format for Bazel Central Registry compatibility
      sig { override.returns(String) }
      def to_s
        @original_version
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("bazel", Dependabot::Bazel::Version)
