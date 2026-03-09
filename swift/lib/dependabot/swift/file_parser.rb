# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/experiments"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/swift/file_parser/dependency_parser"
require "dependabot/swift/file_parser/manifest_parser"
require "dependabot/swift/file_parser/xcode_spm_resolver"
require "dependabot/swift/package_manager"
require "dependabot/swift/language"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        if package_manifest_file
          parse_classic_spm
        elsif xcode_spm_mode?
          parse_xcode_spm
        else
          raise "No Package.swift or Xcode Package.resolved found!"
        end
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          begin
            Ecosystem.new(
              name: ECOSYSTEM,
              language: language,
              package_manager: package_manager
            )
          end,
          T.nilable(Dependabot::Ecosystem)
        )
      end

      private

      # Classic SPM parsing: uses swift CLI via DependencyParser + ManifestParser
      sig { returns(T::Array[Dependabot::Dependency]) }
      def parse_classic_spm
        dependency_set = DependencySet.new

        dependency_parser.parse.map do |dep|
          if dep.top_level?
            source = T.must(dep.requirements.first)[:source]

            requirements = ManifestParser.new(T.must(package_manifest_file), source: source).requirements

            dependency_set << Dependency.new(
              name: dep.name,
              version: dep.version,
              package_manager: dep.package_manager,
              requirements: requirements,
              metadata: dep.metadata
            )
          else
            dependency_set << dep
          end
        end

        dependency_set.dependencies
      end

      # Xcode SPM parsing: delegates to XcodeSpmResolver which parses
      # Package.resolved JSON and enriches with project.pbxproj requirements
      sig { returns(T::Array[Dependabot::Dependency]) }
      def parse_xcode_spm
        XcodeSpmResolver.new(
          xcode_resolved_files: xcode_resolved_files,
          pbxproj_files: pbxproj_files
        ).parse
      end

      sig { returns(T::Boolean) }
      def xcode_spm_mode?
        Dependabot::Experiments.enabled?(:enable_swift_xcode_spm) &&
          xcode_resolved_files.any?
      end

      sig { returns(Dependabot::Swift::FileParser::DependencyParser) }
      def dependency_parser
        DependencyParser.new(
          dependency_files: dependency_files,
          repo_contents_path: repo_contents_path,
          credentials: credentials
        )
      end

      sig { override.void }
      def check_required_files
        return if package_manifest_file

        if Dependabot::Experiments.enabled?(:enable_swift_xcode_spm)
          return if xcode_resolved_files.any?

          raise "No Package.swift or Xcode Package.resolved found!"
        end

        raise "No Package.swift!"
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def package_manifest_file
        # TODO: Select version-specific manifest
        @package_manifest_file ||= T.let(get_original_file("Package.swift"), T.nilable(Dependabot::DependencyFile))
      end

      # All non-support Package.resolved files from Xcode project directories
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def xcode_resolved_files
        @xcode_resolved_files ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?("Package.resolved") &&
              f.name.include?(".xcodeproj/") &&
              !f.support_file?
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      # All project.pbxproj support files
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pbxproj_files
        @pbxproj_files ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?("project.pbxproj") && f.support_file?
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(T.must(package_manager_version)),
          T.nilable(Dependabot::Swift::PackageManager)
        )
      end

      sig { returns(T.nilable(String)) }
      def package_manager_version
        @package_manager_version ||= T.let(
          begin
            version = SharedHelpers.run_shell_command("swift package --version")
            version.strip.gsub(/Swift Package Manager - Swift \s*/, "")
          end,
          T.nilable(String)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(
          begin
            Language.new(T.must(swift_version))
          end,
          T.nilable(Dependabot::Swift::Language)
        )
      end

      sig { returns(T.nilable(String)) }
      def swift_version
        @swift_version ||= T.let(
          begin
            version = SharedHelpers.run_shell_command("swift --version")
            pattern = Dependabot::Ecosystem::VersionManager::DEFAULT_VERSION_PATTERN
            version.match(/Swift version\s*#{pattern}/)&.captures&.first
          end,
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileParsers
  .register("swift", Dependabot::Swift::FileParser)
