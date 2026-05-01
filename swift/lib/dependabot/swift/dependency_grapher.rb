# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/swift/xcode_file_helpers"

module Dependabot
  module Swift
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      extend T::Sig

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        if classic_spm_mode?
          package_resolved || T.must(package_manifest)
        else
          xcode_resolved_file
        end
      end

      private

      # Mirror the FileParser's mode selection: classic SPM takes precedence
      # when Package.swift is present, otherwise use Xcode SPM.
      sig { returns(T::Boolean) }
      def classic_spm_mode?
        !package_manifest.nil?
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def package_manifest
        return @package_manifest if defined?(@package_manifest)

        @package_manifest = T.let(
          dependency_files.find { |f| f.name == "Package.swift" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def package_resolved
        return @package_resolved if defined?(@package_resolved)

        @package_resolved = T.let(
          dependency_files.find { |f| f.name == "Package.resolved" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      # Returns the first Xcode-scoped Package.resolved, chosen deterministically
      # by filename to ensure consistent ownership when multiple Xcode projects exist.
      sig { returns(Dependabot::DependencyFile) }
      def xcode_resolved_file
        file = xcode_resolved_files.min_by(&:name)
        raise DependabotError, "No Package.swift or Xcode Package.resolved found." unless file

        file
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def xcode_resolved_files
        @xcode_resolved_files ||= T.let(
          dependency_files.select do |f|
            XcodeFileHelpers.xcode_resolved_path?(f.name) && !f.support_file?
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(_dependency)
        []
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "swift"
      end
    end
  end
end

Dependabot::DependencyGraphers.register("swift", Dependabot::Swift::DependencyGrapher)
