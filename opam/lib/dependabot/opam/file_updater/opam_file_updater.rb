# typed: strict
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
            new_requirement = T.cast(req[:requirement], T.nilable(String))
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
          # Use non-greedy matching to properly capture leading/trailing whitespace
          dep_regex = /("#{Regexp.escape(dependency_name)}"\s*\{)(\s*)(.*?)(\s*)(\})/

          content.gsub(dep_regex) do |_match|
            prefix = T.must(Regexp.last_match(1))
            leading_space = T.must(Regexp.last_match(2))
            constraints_content = T.must(Regexp.last_match(3))
            trailing_space = T.must(Regexp.last_match(4))
            suffix = T.must(Regexp.last_match(5))

            # Update the constraints while preserving formatting and filters
            new_constraints = update_constraints(constraints_content, new_requirement)

            # Preserve leading/trailing whitespace from original
            "#{prefix}#{leading_space}#{new_constraints}#{trailing_space}#{suffix}"
          end
        end

        sig { params(old_constraints: String, new_requirement: String).returns(String) }
        def self.update_constraints(old_constraints, new_requirement)
          parts = old_constraints.split("&").map(&:strip)
          new_by_operator = build_operator_map(new_requirement)
          updated_parts = replace_version_constraints(parts, new_by_operator)

          # Append any remaining new constraints that weren't matched
          updated_parts += new_by_operator.values unless new_by_operator.empty?

          updated_parts.join(" & ")
        end

        sig { params(requirement: String).returns(T::Hash[String, String]) }
        def self.build_operator_map(requirement)
          new_parts = requirement.split("&").map(&:strip).select { |part| version_constraint?(part) }

          new_parts.each_with_object({}) do |part, hash|
            operator = extract_operator(part)
            hash[operator] = part if operator
          end
        end

        sig { params(parts: T::Array[String], operator_map: T::Hash[String, String]).returns(T::Array[String]) }
        def self.replace_version_constraints(parts, operator_map)
          parts.filter_map do |part|
            if version_constraint?(part)
              replace_or_remove_constraint(part, operator_map)
            else
              part # Keep filters/platform checks as-is
            end
          end
        end

        sig { params(part: String).returns(T::Boolean) }
        def self.version_constraint?(part)
          part.match?(/^[><=!]+\s*"/)
        end

        sig { params(part: String).returns(T.nilable(String)) }
        def self.extract_operator(part)
          match = part.match(/^([><=!]+)\s*/)
          match ? match[1] : nil
        end

        sig { params(part: String, operator_map: T::Hash[String, String]).returns(T.nilable(String)) }
        def self.replace_or_remove_constraint(part, operator_map)
          operator = extract_operator(part)
          return nil unless operator

          # If there's a matching new constraint, use it; otherwise remove this constraint
          operator_map.delete(operator)
        end
      end
    end
  end
end
