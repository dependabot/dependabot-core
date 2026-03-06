# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/experiments"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/swift/file_parser/dependency_parser"
require "dependabot/swift/file_parser/manifest_parser"
require "dependabot/swift/file_parser/package_resolved_parser"
require "dependabot/swift/file_parser/pbxproj_parser"
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

      # Xcode SPM parsing: parses Package.resolved JSON directly, enriches
      # with requirement info from project.pbxproj files
      sig { returns(T::Array[Dependabot::Dependency]) }
      def parse_xcode_spm
        dependency_set = DependencySet.new

        scoped_requirements = aggregate_pbxproj_requirements

        xcode_resolved_files.each do |resolved_file|
          resolved_deps = PackageResolvedParser.new(resolved_file).parse
          xcodeproj_dir = extract_xcodeproj_dir(resolved_file.name)
          pbxproj_requirements = scoped_requirements.fetch(xcodeproj_dir, {})

          resolved_deps.each do |dep|
            enriched = enrich_with_pbxproj_requirements(dep, pbxproj_requirements)
            dependency_set << enriched
          end
        end

        dependency_set.dependencies
      end

      sig { returns(T::Boolean) }
      def xcode_spm_mode?
        Dependabot::Experiments.enabled?(:enable_swift_xcode_spm) &&
          xcode_resolved_files.any?
      end

      # Collects requirement info from all project.pbxproj support files,
      # keyed by xcodeproj directory so each resolved file only sees
      # requirements from its own Xcode project.
      sig { returns(T::Hash[T.nilable(String), T::Hash[String, T::Hash[Symbol, T.untyped]]]) }
      def aggregate_pbxproj_requirements
        scoped = T.let({}, T::Hash[T.nilable(String), T::Hash[String, T::Hash[Symbol, T.untyped]]])

        pbxproj_files.each do |pbxproj_file|
          xcodeproj_dir = extract_xcodeproj_dir(pbxproj_file.name)
          scoped[xcodeproj_dir] ||= {}

          PbxprojParser.new(pbxproj_file).parse.each do |name, req_info|
            T.must(scoped[xcodeproj_dir])[name] = req_info
          end
        end

        scoped
      end

      # Enriches a dependency parsed from Package.resolved with requirement
      # info from the matching project.pbxproj
      sig do
        params(
          dep: Dependabot::Dependency,
          pbxproj_requirements: T::Hash[String, T::Hash[Symbol, T.untyped]]
        ).returns(Dependabot::Dependency)
      end
      def enrich_with_pbxproj_requirements(dep, pbxproj_requirements)
        req_info = pbxproj_requirements[dep.name]
        return dep unless req_info

        pbxproj_file = req_info[:file]
        requirement_str = req_info[:requirement]
        requirement_string = req_info[:requirement_string]

        new_requirements = dep.requirements.map do |req|
          req.merge(
            requirement: requirement_str || req[:requirement],
            file: pbxproj_file,
            metadata: {
              # declaration_string is not applicable for Xcode-managed SPM
              # (no Package.swift manifest to extract it from)
              declaration_string: nil,
              requirement_string: requirement_string
            }.compact
          )
        end

        Dependency.new(
          name: dep.name,
          version: dep.version,
          package_manager: dep.package_manager,
          requirements: new_requirements,
          metadata: dep.metadata
        )
      end

      # Extracts the .xcodeproj directory name from a file path.
      # e.g. "MyApp.xcodeproj/project.xcworkspace/.../Package.resolved" -> "MyApp.xcodeproj"
      # e.g. "sub/dir/App.xcodeproj/project.pbxproj" -> "sub/dir/App.xcodeproj"
      sig { params(path: String).returns(T.nilable(String)) }
      def extract_xcodeproj_dir(path)
        match = path.match(%r{^(.*?\.xcodeproj)/})
        match&.captures&.first
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
          return if dependency_files.any? { |f| f.name.end_with?("Package.resolved") && f.name.include?(".xcodeproj/") }

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
