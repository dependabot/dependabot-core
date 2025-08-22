# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

require "dependabot/vcpkg"
require "dependabot/vcpkg/language"
require "dependabot/vcpkg/package_manager"

module Dependabot
  module Vcpkg
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dependency_files.each do |file|
          parsed_dependencies = parse_dependency_file(file)
          if parsed_dependencies.is_a?(Array)
            parsed_dependencies.each { |dependency| dependency_set << dependency }
          elsif parsed_dependencies
            dependency_set << parsed_dependencies
          end
        end

        dependency_set.dependencies
      end

      sig { override.returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any? { |f| f.name == VCPKG_JSON_FILENAME }

        raise Dependabot::DependencyFileNotFound, VCPKG_JSON_FILENAME
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T.any(T.nilable(Dependabot::Dependency), T::Array[Dependabot::Dependency])) }
      def parse_dependency_file(dependency_file)
        return unless dependency_file.content

        case dependency_file.name
        when VCPKG_JSON_FILENAME then parse_vcpkg_json(dependency_file)
        when VCPKG_CONFIGURATION_JSON_FILENAME then nil # TODO
        end
      end

      sig { params(dependency_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_vcpkg_json(dependency_file)
        contents = T.must(dependency_file.content)
        parsed_json = JSON.parse(contents)
        
        dependencies = T.let([], T::Array[Dependabot::Dependency])
        
        # Add baseline dependency if present
        baseline = parsed_json["builtin-baseline"]
        if baseline
          dependencies << build_baseline_dependency(baseline: baseline, file: dependency_file)
        end
        
        # Parse individual package dependencies
        package_dependencies = parsed_json["dependencies"]
        if package_dependencies.is_a?(Array)
          package_dependencies.each do |dep|
            package_dep = parse_package_dependency(dep, dependency_file)
            dependencies << package_dep if package_dep
          end
        end
        
        dependencies
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, T.must(dependency_files.first).path
      end

      sig { params(baseline: String, file: Dependabot::DependencyFile).returns(Dependabot::Dependency) }
      def build_baseline_dependency(baseline:, file:)
        Dependabot::Dependency.new(
          name: VCPKG_DEFAULT_BASELINE_DEPENDENCY_NAME,
          version: baseline,
          package_manager: "vcpkg",
          requirements: [{
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: VCPKG_DEFAULT_BASELINE_URL,
              ref: VCPKG_DEFAULT_BASELINE_DEFAULT_BRANCH
            },
            file: file.name
          }]
        )
      end

      sig { params(dependency_spec: T.any(String, T::Hash[String, T.untyped]), file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::Dependency)) }
      def parse_package_dependency(dependency_spec, file)
        if dependency_spec.is_a?(String)
          # For now, ignore simple string dependencies to maintain backward compatibility
          # These don't have version constraints, so they're not actionable by Dependabot
          return nil
        elsif dependency_spec.is_a?(Hash)
          name = dependency_spec["name"]
          return nil unless name.is_a?(String) && !name.empty?

          # Handle version constraints
          requirement = nil
          
          # Check for version>=
          if dependency_spec.key?("version>=")
            version_constraint = dependency_spec["version>="]
            if version_constraint.is_a?(String) && !version_constraint.empty?
              requirement = ">= #{version_constraint}"
            end
          end
          
          # Only create dependency if there's a version constraint
          # This ensures we only track dependencies that Dependabot can actually update
          return nil unless requirement

          # Could add support for other constraint types here in the future:
          # version>, version<=, version<, version=, etc.

          build_package_dependency(name: name, requirement: requirement, file: file)
        end
      end

      sig { params(name: String, requirement: T.nilable(String), file: Dependabot::DependencyFile).returns(Dependabot::Dependency) }
      def build_package_dependency(name:, requirement:, file:)
        Dependabot::Dependency.new(
          name: name,
          version: nil, # No locked version for vcpkg packages yet
          package_manager: "vcpkg",
          requirements: [{
            requirement: requirement,
            groups: [],
            source: nil, # vcpkg packages don't have individual sources like git dependencies
            file: file.name
          }]
        )
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(PackageManager.new, T.nilable(Dependabot::Vcpkg::PackageManager))
      end

      sig { returns(Ecosystem::VersionManager) }
      def language
        @language ||= T.let(Language.new, T.nilable(Dependabot::Vcpkg::Language))
      end
    end
  end
end

Dependabot::FileParsers.register("vcpkg", Dependabot::Vcpkg::FileParser)
