# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

require "dependabot/azure_pipelines/constants"

module Dependabot
  module AzurePipelines
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/\.ya?ml$/]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        dependency_files.filter_map do |file|
          updated_content = updated_file_content(file)
          next if updated_content.nil? || updated_content == file.content

          updated_file(file: file, content: updated_content)
        end
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No dependency files!"
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def updated_file_content(file)
        content = file.content
        return nil if content.nil?

        dependencies.each do |dependency|
          content = replace_task_version(content, dependency, file)
        end

        content
      end

      # Rewriting the reference in place rather than re-emitting the YAML keeps the
      # pipeline's comments, quoting and indentation intact.
      sig do
        params(
          content: String,
          dependency: Dependabot::Dependency,
          file: Dependabot::DependencyFile
        ).returns(String)
      end
      def replace_task_version(content, dependency, file)
        old_requirement = requirement_for(file, dependency.previous_requirements)
        new_requirement = requirement_for(file, dependency.requirements)
        return content if old_requirement.nil? || new_requirement.nil?
        return content if old_requirement == new_requirement

        updated = content.gsub(task_reference_regex(dependency.name, old_requirement)) do
          "#{Regexp.last_match(1)}#{Regexp.last_match(2)}@#{new_requirement}"
        end

        raise Dependabot::DependencyFileContentNotChanged, file.path if updated == content

        updated
      end

      # Matches `task: Maven@3` in bare, single-quoted and double-quoted form, anchored
      # on the `task` key so a task name appearing elsewhere is left alone. Azure DevOps
      # treats task names case-insensitively, so the name is matched that way and echoed
      # back from the file rather than from the dependency, leaving the author's spelling
      # as they wrote it.
      sig { params(name: String, requirement: String).returns(Regexp) }
      def task_reference_regex(name, requirement)
        /
          (^[ \t]*-?[ \t]*task:[ \t]*["']?)
          (#{Regexp.escape(name)})@#{Regexp.escape(requirement)}
          (?=[ \t]*["']?[ \t]*(?:\#.*)?$)
        /xi
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          requirements: T.nilable(T::Array[Dependabot::DependencyRequirement])
        ).returns(T.nilable(String))
      end
      def requirement_for(file, requirements)
        requirement = requirements
                      &.find { |candidate| candidate.file == file.name }
                      &.requirement

        requirement.is_a?(String) ? requirement : nil
      end
    end
  end
end

Dependabot::FileUpdaters.register("azure_pipelines", Dependabot::AzurePipelines::FileUpdater)
