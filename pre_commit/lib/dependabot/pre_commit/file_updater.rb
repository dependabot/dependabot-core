# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module PreCommit
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        dependency_files.each do |file|
          next unless requirement_changed?(file, dependency)

          updated_files <<
            updated_file(
              file: file,
              content: updated_config_file_content(file)
            )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { returns(Dependabot::Dependency) }
      def dependency
        # Pre-commit will only ever be updating a single dependency
        T.must(dependencies.first)
      end

      sig { override.void }
      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No pre-commit config files!"
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_config_file_content(file)
        updated_requirement_pairs =
          dependency.requirements.zip(T.must(dependency.previous_requirements))
                    .reject do |new_req, old_req|
            next true if new_req[:file] != file.name

            new_req[:source] == T.must(old_req)[:source]
          end

        updated_content = T.must(file.content)

        updated_requirement_pairs.each do |new_req, old_req|
          next unless new_req.fetch(:source).fetch(:type) == "git"

          old_ref = T.must(old_req).fetch(:source).fetch(:ref)
          new_ref = new_req.fetch(:source).fetch(:ref)

          # Replace the old rev value with the new rev value in the YAML
          # The pattern matches: "rev: <old_ref>" where old_ref may be a tag, commit SHA, or version
          updated_content =
            updated_content
            .gsub(
              /^(\s*rev:\s+)#{Regexp.escape(old_ref)}(\s*(?:#.*)?)?$/
            ) do |match|
              # Preserve the indentation and any trailing comment
              match.gsub(old_ref, new_ref)
            end
        end

        updated_content
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("pre_commit", Dependabot::PreCommit::FileUpdater)
