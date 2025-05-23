# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"

module Dependabot
  module RustToolchain
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dependency_files.each do |dependency_file|
          dependency = parse_dependency_file(dependency_file)
          next unless dependency

          dependency_set << dependency
        end

        dependency_set.dependencies
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No dependency files!"
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::Dependency)) }
      def parse_dependency_file(dependency_file)
        content = T.must(dependency_file.content).strip

        channel = case dependency_file.name
                  when /\.toml$/
                    parse_toml_toolchain(content)
                  else
                    parse_plaintext_toolchain(content)
                  end

        return if channel.nil?

        Dependency.new(
          name: "rust-toolchain",
          version: channel,
          requirements: [{
            file: dependency_file.name
          }],
          package_manager: "rust_toolchain"
        )
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
    end
  end
end

Dependabot::FileParsers.register("rust_toolchain", Dependabot::RustToolchain::FileParser)
