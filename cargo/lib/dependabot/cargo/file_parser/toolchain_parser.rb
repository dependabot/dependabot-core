# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers/base"

require "dependabot/cargo/file_parser/toolchain_channel_parser"

module Dependabot
  module Cargo
    class FileParser < Dependabot::FileParsers::Base
      class ToolchainParser
        extend T::Sig

        sig { params(toolchain_file: Dependabot::DependencyFile).void }
        def initialize(toolchain_file)
          @toolchain_file = toolchain_file
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def parse
          return unless toolchain_file.content

          raw_toolchain_channel = extract_toolchain_channel
          toolchain_channel = parse_toolchain_channel(raw_toolchain_channel)

          return if toolchain_channel.nil?

          Dependency.new(
            name: "rust-toolchain",
            version: raw_toolchain_channel,
            requirements: [],
            package_manager: "cargo",
            metadata: {
              toolchain_channel: toolchain_channel
            }
          )
        end

        private

        sig { returns(String) }
        def extract_toolchain_channel
          @extract_toolchain_channel ||= T.let(extract_toolchain_file, T.nilable(String))
        end

        sig { returns(String) }
        def extract_toolchain_file
          content = T.must(toolchain_file.content).strip

          case toolchain_file.name
          when /\.toml$/
            parse_toml_toolchain(content)
          else
            parse_plaintext_toolchain(content)
          end
        end

        sig { params(content: String).returns(String) }
        def parse_toml_toolchain(content)
          parsed = TomlRB.parse(content)

          channel = parsed.dig("toolchain", "channel")
          return channel if channel

          Dependabot.logger.warn("No toolchain section found in rust-toolchain.toml file.")
          raise Dependabot::DependencyFileNotParseable, "rust-toolchain.toml"
        rescue TomlRB::ParseError => e
          Dependabot.logger.warn("Failed to parse rust-toolchain.toml file: #{e.message}")
          raise Dependabot::DependencyFileNotParseable, "rust-toolchain.toml"
        end

        sig { params(content: String).returns(String) }
        def parse_plaintext_toolchain(content) = content.strip

        sig { params(raw_toolchain_channel: String).returns(T.nilable(T::Hash[Symbol, T.nilable(String)])) }
        def parse_toolchain_channel(raw_toolchain_channel)
          ToolchainChannelParser.new(
            raw_toolchain_channel
          ).parse
        end

        # Using shorthand accessor notation
        sig { returns(Dependabot::DependencyFile) }
        attr_reader :toolchain_file
      end
    end
  end
end
