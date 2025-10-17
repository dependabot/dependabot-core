# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/errors"
require "dependabot/rust_toolchain/models/rust_toolchain_config"

module Dependabot
  module RustToolchain
    module Models
      # Typed struct for rust-toolchain.toml file structure
      # https://rust-lang.github.io/rustup/overrides.html#the-toolchain-file
      class RustToolchainToml < T::ImmutableStruct
        extend T::Sig

        # The [toolchain] section containing the toolchain configuration
        # This is the only top-level section currently supported
        const :toolchain, RustToolchainConfig

        sig { params(toml_string: String).returns(RustToolchainToml) }
        def self.from_toml(toml_string)
          parsed_data = TomlRB.parse(toml_string)
          data = T.cast(parsed_data, T::Hash[String, T.untyped])

          toolchain_data = T.cast(data["toolchain"], T::Hash[String, T.untyped])
          new(
            toolchain: RustToolchainConfig.from_hash(toolchain_data)
          )
        rescue TomlRB::ParseError, TypeError => e
          raise Dependabot::DependencyFileNotParseable, "Invalid TOML syntax: #{e.message}"
        end

        # Extracts the channel from the toolchain configuration
        sig { returns(String) }
        def channel
          toolchain.channel
        end
      end
    end
  end
end
