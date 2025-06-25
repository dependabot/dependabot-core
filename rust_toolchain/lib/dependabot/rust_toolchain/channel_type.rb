# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module RustToolchain
    class ChannelType < T::Enum
      enums do
        # Represents a version with a specific version number
        Version = new("Version")

        # Represents a channel with a date, e.g., "nightly-2023-10-01"
        DatedStability = new("DatedStability")

        # Represents a channel without a date, e.g., "stable" or "beta"
        Stability = new("Stability")

        # Represents an unknown or unsupported type
        Unknown = new("Unknown")
      end
    end
  end
end
