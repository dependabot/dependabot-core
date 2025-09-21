# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module RustToolchain
    module Models
      # Typed struct for the [toolchain] section of rust-toolchain.toml files
      # https://rust-lang.github.io/rustup/overrides.html#the-toolchain-file
      class RustToolchainConfig < T::ImmutableStruct
        extend T::Sig

        # The channel specifies which toolchain to use
        # Format: "(<channel>[-<date>])|<custom toolchain name>"
        # Examples: "stable", "beta", "nightly", "nightly-2020-07-10", "1.70.0"
        const :channel, String

        # Creates a RustToolchainConfig from a hash representation
        sig { params(data: T::Hash[String, T.untyped]).returns(RustToolchainConfig) }
        def self.from_hash(data)
          new(
            channel: T.cast(data["channel"], String)
          )
        rescue TypeError => e
          raise Dependabot::DependencyFileNotParseable, "Invalid toolchain config: #{e.message}"
        end
      end
    end
  end
end
