# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

require "dependabot/rust_toolchain"

module Dependabot
  module RustToolchain
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        rust_toolchain_files.each do |file|
          next unless file_changed?(file)

          updated_files << updated_file(file: file, content: update(T.must(file.content)))
        end

        updated_files
      end

      private

      sig { returns(Dependabot::Dependency) }
      def dependency
        T.must(dependencies.first)
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "Could not find any dependency files to update. " \
              "Expected to find a file named 'rust-toolchain' or 'rust-toolchain.toml'."
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def rust_toolchain_files
        dependency_files.select do |f|
          f.name == RUST_TOOLCHAIN_FILENAME || f.name == RUST_TOOLCHAIN_TOML_FILENAME
        end
      end

      sig { params(content: String).returns(String) }
      def update(content)
        content.gsub(T.must(dependency.previous_version), T.must(dependency.version))
      end
    end
  end
end

Dependabot::FileUpdaters.register("rust_toolchain", Dependabot::RustToolchain::FileUpdater)
