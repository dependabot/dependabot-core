# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/swift/file_parser"
require "dependabot/swift/file_parser/package_resolved_parser"
require "dependabot/swift/file_parser/pbxproj_parser"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      # Orchestrates Xcode-managed SwiftPM dependency parsing.
      #
      # Parses Package.resolved JSON files found inside .xcodeproj directories,
      # then enriches each dependency with requirement info extracted from the
      # corresponding project.pbxproj files.
      class XcodeSpmResolver
        extend T::Sig

        sig do
          params(
            xcode_resolved_files: T::Array[Dependabot::DependencyFile],
            pbxproj_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def initialize(xcode_resolved_files:, pbxproj_files:)
          @xcode_resolved_files = xcode_resolved_files
          @pbxproj_files = pbxproj_files
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def parse
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          scoped_requirements = aggregate_pbxproj_requirements
          all_requirements = merge_all_requirements(scoped_requirements)

          xcode_resolved_files.each do |resolved_file|
            resolved_deps = PackageResolvedParser.new(resolved_file).parse
            xcode_scope_dir = extract_xcode_scope_dir(resolved_file.name)
            pbxproj_requirements = scoped_requirements.fetch(xcode_scope_dir, all_requirements)

            resolved_deps.each do |dep|
              enriched = enrich_with_pbxproj_requirements(dep, pbxproj_requirements)
              dependency_set << enriched
            end
          end

          dependency_set.dependencies
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :xcode_resolved_files

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :pbxproj_files

        # Collects requirement info from all project.pbxproj support files,
        # keyed by Xcode scope directory so each resolved file can be enriched
        # by requirements from its closest matching Xcode scope.
        sig { returns(T::Hash[T.nilable(String), T::Hash[String, T::Hash[Symbol, T.untyped]]]) }
        def aggregate_pbxproj_requirements
          scoped = T.let({}, T::Hash[T.nilable(String), T::Hash[String, T::Hash[Symbol, T.untyped]]])

          pbxproj_files.each do |pbxproj_file|
            xcode_scope_dir = extract_xcode_scope_dir(pbxproj_file.name)
            scoped[xcode_scope_dir] ||= {}

            PbxprojParser.new(pbxproj_file).parse.each do |name, req_info|
              T.must(scoped[xcode_scope_dir])[name] = req_info
            end
          end

          scoped
        end

        sig do
          params(
            scoped_requirements: T::Hash[T.nilable(String), T::Hash[String, T::Hash[Symbol, T.untyped]]]
          ).returns(T::Hash[String, T::Hash[Symbol, T.untyped]])
        end
        def merge_all_requirements(scoped_requirements)
          scoped_requirements.values.each_with_object({}) do |requirements, merged|
            requirements.each { |name, req_info| merged[name] = req_info }
          end
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
          kind = req_info[:kind]

          new_requirements = dep.requirements.map do |req|
            req.merge(
              requirement: requirement_str || req[:requirement],
              file: pbxproj_file,
              metadata: {
                # declaration_string is not applicable for Xcode-managed SPM
                # (no Package.swift manifest to extract it from)
                declaration_string: nil,
                requirement_string: requirement_string,
                kind: kind
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

        # Extracts the Xcode scope directory (.xcodeproj or .xcworkspace)
        # from a file path.
        sig { params(path: String).returns(T.nilable(String)) }
        def extract_xcode_scope_dir(path)
          match = path.match(%r{^(.*?\.(?:xcodeproj|xcworkspace))/})
          match&.captures&.first
        end
      end
    end
  end
end
