# typed: strict
# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/swift/native_requirement"
require "dependabot/swift/version"

module Dependabot
  module Swift
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RequirementsUpdater
        extend T::Sig

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            target_version: T.nilable(T.any(String, Gem::Version)),
            xcode_mode: T::Boolean,
            target_commit_sha: T.nilable(String)
          ).void
        end
        def initialize(requirements:, target_version:, xcode_mode: false, target_commit_sha: nil)
          @requirements = requirements
          @xcode_mode = xcode_mode
          @target_commit_sha = T.let(target_commit_sha, T.nilable(String))

          return unless target_version && Version.correct?(target_version)

          @target_version = T.let(Version.new(target_version), Dependabot::Version)
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          return updated_xcode_requirements if xcode_mode

          NativeRequirement.map_requirements(requirements) do |requirement|
            T.must(requirement.update_if_needed(T.must(target_version)))
          end
        end

        private

        sig { returns(T::Array[T.untyped]) }
        attr_reader :requirements

        sig { returns(T.nilable(Gem::Version)) }
        attr_reader :target_version

        sig { returns(T::Boolean) }
        attr_reader :xcode_mode

        sig { returns(T.nilable(String)) }
        attr_reader :target_commit_sha

        # For Xcode projects, we update the version in the requirement while preserving the kind.
        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_xcode_requirements
          requirements.map do |req|
            next req unless target_version

            updated_req = update_xcode_requirement(req)
            updated_req
          end
        end

        sig { params(requirement: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def update_xcode_requirement(requirement)
          metadata = requirement[:metadata] || {}
          requirement_string = metadata[:requirement_string]
          kind = metadata[:kind]

          new_requirement_string = build_xcode_requirement_string(requirement_string, kind)
          new_requirement = build_xcode_requirement(requirement_string, kind)

          # Update source ref to target version
          updated_source = update_source_ref(requirement[:source])

          requirement.merge(
            requirement: new_requirement,
            source: updated_source,
            metadata: metadata.merge(
              requirement_string: new_requirement_string
            ).compact
          )
        end

        sig do
          params(
            source: T.nilable(T::Hash[T.any(String, Symbol), T.untyped])
          ).returns(T.nilable(T::Hash[T.any(String, Symbol), T.untyped]))
        end
        def update_source_ref(source)
          return source unless source && target_version

          # Use commit SHA if available (for revision field in Package.resolved),
          # otherwise fall back to version string
          ref = target_commit_sha || target_version.to_s

          updated_source = source.dup
          updated_source[:ref] = ref
          updated_source["ref"] = ref
          updated_source
        end

        sig do
          params(
            requirement_string: T.nilable(String),
            kind: T.nilable(String)
          ).returns(T.nilable(String))
        end
        def build_xcode_requirement_string(requirement_string, kind)
          return requirement_string unless target_version

          case kind
          when "upToNextMajorVersion"
            "from: \"#{target_version}\""
          when "upToNextMinorVersion"
            ".upToNextMinor(from: \"#{target_version}\")"
          when "exactVersion"
            "exact: \"#{target_version}\""
          when "versionRange"
            max = extract_version_range_max(requirement_string)
            "\"#{target_version}\"..<\"#{max}\""
          else
            # Default: update to exact version for unknown kinds
            "exact: \"#{target_version}\""
          end
        end

        sig do
          params(
            requirement_string: T.nilable(String),
            kind: T.nilable(String)
          ).returns(T.nilable(String))
        end
        def build_xcode_requirement(requirement_string, kind)
          return nil unless target_version

          case kind
          when "upToNextMajorVersion"
            max = bump_version(target_version.to_s, :major)
            ">= #{target_version}, < #{max}"
          when "upToNextMinorVersion"
            max = bump_version(target_version.to_s, :minor)
            ">= #{target_version}, < #{max}"
          when "exactVersion"
            "= #{target_version}"
          when "versionRange"
            max = extract_version_range_max(requirement_string)
            ">= #{target_version}, < #{max}"
          else
            # Default: exact version
            "= #{target_version}"
          end
        end

        # Extracts the upper bound from a versionRange requirement string.
        # Format: "min"..<"max" or "min"..."max"
        sig { params(requirement_string: T.nilable(String)).returns(String) }
        def extract_version_range_max(requirement_string)
          return bump_version(target_version.to_s, :major) unless requirement_string

          # Match patterns like "1.0.0"..<"2.0.0" or "1.0.0"..."2.0.0"
          match = requirement_string.match(/\.{2,3}<?"(\d+\.\d+\.\d+)"/)
          return bump_version(target_version.to_s, :major) unless match

          match[1].to_s
        end

        sig { params(version_str: String, bump_type: Symbol).returns(String) }
        def bump_version(version_str, bump_type)
          parts = version_str.split(".").map(&:to_i)

          case bump_type
          when :major
            [(parts[0] || 0) + 1, 0, 0]
          when :minor
            [parts[0] || 0, (parts[1] || 0) + 1, 0]
          else
            parts
          end.join(".")
        end
      end
    end
  end
end
