# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"

require "dependabot/rust_toolchain/models/rust_toolchain_toml"
require "dependabot/rust_toolchain/package_manager"

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

      sig { returns(Dependabot::Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Dependabot::Ecosystem.new(
            name: "rust_toolchain",
            package_manager: package_manager
          ),
          T.nilable(Dependabot::Ecosystem)
        )
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "Could not find any dependency files to parse. " \
              "Expected to find a file named 'rust-toolchain' or 'rust-toolchain.toml'."
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

        return if channel.empty?

        Dependency.new(
          name: "rust-toolchain",
          version: channel,
          requirements: [{
            file: dependency_file.name,
            requirement: channel,
            groups: [],
            source: nil
          }],
          package_manager: "rust_toolchain"
        )
      end

      sig { params(content: String).returns(String) }
      def parse_toml_toolchain(content)
        toolchain_toml = Models::RustToolchainToml.from_toml(content)
        toolchain_toml.channel
      end

      sig { params(content: String).returns(String) }
      def parse_plaintext_toolchain(content) = content.strip

      sig { returns(Dependabot::Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          Dependabot::RustToolchain::RustToolchainPackageManager.new,
          T.nilable(Dependabot::Ecosystem::VersionManager)
        )
      end
    end
  end
end

Dependabot::FileParsers.register("rust_toolchain", Dependabot::RustToolchain::FileParser)
