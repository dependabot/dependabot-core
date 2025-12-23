# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/lean"
require "dependabot/lean/version"
require "dependabot/lean/lake/manifest_parser"

module Dependabot
  module Lean
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      # Matches: leanprover/lean4:v4.26.0 or leanprover/lean4:v4.26.0-rc2
      TOOLCHAIN_REGEX = %r{\Aleanprover/lean4:v(.+)\z}

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependencies = []

        # Parse toolchain file (Lean compiler version)
        toolchain_dep = parse_toolchain_file
        dependencies << toolchain_dep if toolchain_dep

        # Parse Lake manifest (package dependencies)
        if lake_manifest_file
          lake_deps = Lake::ManifestParser.new(manifest_file: T.must(lake_manifest_file)).parse
          dependencies.concat(lake_deps)
        end

        dependencies
      end

      sig { returns(Dependabot::Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Dependabot::Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Dependabot::Ecosystem)
        )
      end

      private

      sig { returns(T.nilable(Dependabot::Dependency)) }
      def parse_toolchain_file
        file = lean_toolchain_file
        return unless file

        content = T.must(file.content).strip
        version = parse_version(content)
        return unless version
        return unless Lean::Version.correct?(version)

        Dependabot::Dependency.new(
          name: "lean4",
          version: version,
          requirements: [{
            requirement: version,
            file: file.name,
            groups: [],
            source: { type: "default" }
          }],
          package_manager: PACKAGE_MANAGER
        )
      end

      sig { params(content: String).returns(T.nilable(String)) }
      def parse_version(content)
        match = content.match(TOOLCHAIN_REGEX)
        return unless match

        match[1]
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lean_toolchain_file
        @lean_toolchain_file ||= T.let(
          dependency_files.find { |f| f.name == LEAN_TOOLCHAIN_FILENAME },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lake_manifest_file
        @lake_manifest_file ||= T.let(
          dependency_files.find { |f| f.name == LAKE_MANIFEST_FILENAME },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(Dependabot::Ecosystem::VersionManager) }
      def package_manager
        LeanPackageManager.new
      end

      sig { returns(Dependabot::Ecosystem::VersionManager) }
      def language
        LeanLanguage.new(lean_version)
      end

      sig { returns(T.nilable(String)) }
      def lean_version
        file = lean_toolchain_file
        return unless file

        content = T.must(file.content).strip
        parse_version(content)
      end

      sig { override.void }
      def check_required_files
        return if lean_toolchain_file || lake_manifest_file

        raise Dependabot::DependencyFileNotFound.new(
          nil,
          "No #{LEAN_TOOLCHAIN_FILENAME} or #{LAKE_MANIFEST_FILENAME} found"
        )
      end
    end
  end
end

Dependabot::FileParsers.register("lean", Dependabot::Lean::FileParser)
