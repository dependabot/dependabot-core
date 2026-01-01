# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Opam
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Updates opam files with new dependency versions
      class OpamFileUpdater
        extend T::Sig

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def self.update_dependency_version(content:, dependency:)
          updated_content = content.dup

          # Get new version from dependency
          new_version = dependency.version
          return content unless new_version

          # Get new requirements
          new_requirements = dependency.requirements

          new_requirements.each do |req|
            new_requirement = req[:requirement]
            next unless new_requirement

            # Find and update the dependency in the opam file
            updated_content = update_dependency_in_content(
              content: updated_content,
              dependency_name: dependency.name,
              new_requirement: new_requirement
            )
          end

          updated_content
        end

        sig do
          params(
            content: String,
            dependency_name: String,
            new_requirement: String
          ).returns(String)
        end
        def self.update_dependency_in_content(content:, dependency_name:, new_requirement:)
          # Pattern to match: "package-name" { version-constraints }
          # We need to update the version constraints

          # Build regex to find the dependency
          dep_regex = /("#{Regexp.escape(dependency_name)}"\s*\{)([^}]+)(\})/

          content.gsub(dep_regex) do |_match|
            prefix = T.must(Regexp.last_match(1))
            old_constraints = T.must(Regexp.last_match(2))
            suffix = T.must(Regexp.last_match(3))

            # Update the constraints while preserving formatting and filters
            new_constraints = update_constraints(old_constraints, new_requirement)

            "#{prefix}#{new_constraints}#{suffix}"
          end
        end

        sig { params(old_constraints: String, new_requirement: String).returns(String) }
        def self.update_constraints(old_constraints, new_requirement)
          # Parse old constraints to preserve filters (with-test, etc.)
          parts = old_constraints.split("&").map(&:strip)

          # Separate version constraints from filters
          version_parts = []
          filter_parts = []

          parts.each do |part|
            if part.match?(/[><=!]+\s*"[^"]*"/)
              # This is a version constraint
              version_parts << part
            else
              # This is a filter or other constraint
              filter_parts << part
            end
          end

          # Replace version constraints with new requirement
          new_parts = new_requirement.split("&").map(&:strip)

          # Combine with preserved filters
          all_parts = new_parts + filter_parts

          # Format with proper spacing
          " " + all_parts.join(" & ") + " "
        end
      end
    end
  end
end
