# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

require "dependabot/rust_toolchain"

module Dependabot
  module RustToolchain
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? do |filename|
          basename = File.basename(filename)
          basename == RUST_TOOLCHAIN_TOML_FILENAME || basename == RUST_TOOLCHAIN_FILENAME
        end
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a #{RUST_TOOLCHAIN_TOML_FILENAME} or #{RUST_TOOLCHAIN_FILENAME} file"
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        files = [rust_toolchain_toml_file, rust_toolchain_file].compact

        return files unless files.empty?

        raise Dependabot::DependencyFileNotFound.new(
          nil,
          self.class.required_files_message
        )
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def rust_toolchain_toml_file = fetch_file_if_present(RUST_TOOLCHAIN_TOML_FILENAME)

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def rust_toolchain_file = fetch_file_if_present(RUST_TOOLCHAIN_FILENAME)
    end
  end
end

Dependabot::FileFetchers.register("rust_toolchain", Dependabot::RustToolchain::FileFetcher)
