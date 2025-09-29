# typed: strict
# frozen_string_literal: true

require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/package/registry_finder"
require "dependabot/npm_and_yarn/registry_parser"
require "dependabot/shared_helpers"

class DependencyRequirement < T::Struct
  const :file, String
  const :requirement, String
  const :groups, T::Array[String]
  const :source, T.nilable(String)
end

module Dependabot
  module NpmAndYarn
    class FileUpdater
      class PnpmWorkspaceUpdater
        extend T::Sig

        sig do
          params(
            workspace_file: Dependabot::DependencyFile,
            dependencies: T::Array[Dependabot::Dependency]
          ).void
        end
        def initialize(workspace_file:, dependencies:)
          @dependencies = dependencies
          @workspace_file = workspace_file
        end

        sig { returns(Dependabot::DependencyFile) }
        def updated_pnpm_workspace
          updated_file = workspace_file.dup
          updated_file.content = updated_pnpm_workspace_content
          updated_file
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :workspace_file

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T.nilable(String)) }
        def updated_pnpm_workspace_content
          content = workspace_file.content.dup
          dependencies.each do |dependency|
            content = update_dependency_versions(T.must(content), dependency)
          end

          content
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_dependency_versions(content, dependency)
          new_requirements(dependency).each do |requirement|
            content = replace_version_in_content(
              content: content,
              dependency: dependency,
              old_requirement: T.must(old_requirement(dependency, requirement)),
              new_requirement: requirement
            )
          end

          content
        end

        sig do
          params(
            content: String,
            dependency: Dependabot::Dependency,
            old_requirement: DependencyRequirement,
            new_requirement: DependencyRequirement
          ).returns(String)
        end
        def replace_version_in_content(content:, dependency:, old_requirement:, new_requirement:)
          old_version = old_requirement.requirement
          new_version = new_requirement.requirement

          pattern = build_replacement_pattern(
            dependency_name: dependency.name,
            version: old_version
          )

          replacement = build_replacement_string(
            dependency_name: dependency.name,
            version: new_version
          )

          content.gsub(pattern, replacement)
        end

        sig { params(dependency_name: String, version: String).returns(Regexp) }
        def build_replacement_pattern(dependency_name:, version:)
          /(["']?)#{dependency_name}\1:\s*(["']?)#{Regexp.escape(version)}\2/
        end

        sig { params(dependency_name: String, version: String).returns(String) }
        def build_replacement_string(dependency_name:, version:)
          "\\1#{dependency_name}\\1: \\2#{version}\\2"
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Array[DependencyRequirement]) }
        def new_requirements(dependency)
          dependency.requirements
                    .select { |r| r[:file] == workspace_file.name }
                    .map do |r|
            DependencyRequirement.new(
              file: r[:file],
              requirement: r[:requirement],
              groups: r[:groups],
              source: r[:source]
            )
          end
        end

        sig do
          params(
            dependency: Dependabot::Dependency,
            new_requirement: DependencyRequirement
          ).returns(T.nilable(DependencyRequirement))
        end
        def old_requirement(dependency, new_requirement)
          matching_req = T.must(dependency.previous_requirements).find { |r| r[:groups] == new_requirement.groups }

          return nil if matching_req.nil?

          DependencyRequirement.new(
            file: matching_req[:file],
            requirement: matching_req[:requirement],
            groups: matching_req[:groups],
            source: matching_req[:source]
          )
        end
      end
    end
  end
end
