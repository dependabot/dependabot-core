# typed: strong
# frozen_string_literal: true

# NOTE: This file was scaffolded automatically but is OPTIONAL.
# If your ecosystem uses standard semantic versioning without special logic,
# you can safely delete this file and remove the require from lib/dependabot/bazel.rb

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Bazel
    class Version < Dependabot::Version
      extend T::Sig

      # TODO: Implement custom version comparison logic if needed
      # Example: Handle pre-release versions, build metadata, etc.
      # If standard semantic versioning is sufficient, delete this file
    end
  end
end

Dependabot::Utils
  .register_version_class("bazel", Dependabot::Bazel::Version)
