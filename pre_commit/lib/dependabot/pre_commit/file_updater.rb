# typed: strong
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

        updated_files.reject! { |f| dependency_files.include?(T.cast(f, Dependabot::DependencyFile)) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { returns(Dependabot::Dependency) }
      def dependency
        T.must(dependencies.first)
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No pre-commit config files!"
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_config_file_content(file)
        updated_requirement_pairs = requirement_pairs_for_file(file)
        updated_content = T.must(file.content)

        updated_requirement_pairs.each do |new_req, old_req|
          updated_content = apply_requirement_update(updated_content, new_req, old_req)
        end

        updated_content
      end

      sig do
        params(file: Dependabot::DependencyFile)
          .returns(T::Array[[T::Hash[Symbol, T.untyped], T::Hash[Symbol, T.untyped]]])
      end
      def requirement_pairs_for_file(file)
        pairs = dependency.requirements.zip(T.must(dependency.previous_requirements))
        filtered_pairs = pairs.reject do |new_req, old_req|
          next true unless old_req

          file_name = T.cast(new_req[:file], T.nilable(String))
          next true if file_name != file.name

          new_source = T.cast(new_req[:source], T.nilable(T::Hash[Symbol, T.untyped]))
          old_source = T.cast(old_req[:source], T.nilable(T::Hash[Symbol, T.untyped]))
          new_source == old_source
        end

        filtered_pairs.map { |new_req, old_req| [new_req, T.must(old_req)] }
      end

      sig do
        params(
          content: String,
          new_req: T::Hash[Symbol, T.untyped],
          old_req: T::Hash[Symbol, T.untyped]
        ).returns(String)
      end
      def apply_requirement_update(content, new_req, old_req)
        new_source = T.cast(new_req.fetch(:source), T::Hash[Symbol, T.untyped])
        source_type = T.cast(new_source.fetch(:type), String)

        case source_type
        when "git"
          apply_git_requirement_update(content, new_req, old_req)
        when "additional_dependency"
          apply_additional_dependency_update(content, new_req, old_req)
        else
          content
        end
      end

      sig do
        params(
          content: String,
          new_req: T::Hash[Symbol, T.untyped],
          old_req: T::Hash[Symbol, T.untyped]
        ).returns(String)
      end
      def apply_git_requirement_update(content, new_req, old_req)
        new_source = T.cast(new_req.fetch(:source), T::Hash[Symbol, T.untyped])
        old_source = T.cast(old_req.fetch(:source), T::Hash[Symbol, T.untyped])
        repo_url = T.cast(old_source.fetch(:url), String)
        old_ref = T.cast(old_source.fetch(:ref), String)
        new_ref = T.cast(new_source.fetch(:ref), String)

        replace_ref_in_content(content, repo_url, old_ref, new_ref)
      end

      sig do
        params(
          content: String,
          new_req: T::Hash[Symbol, T.untyped],
          old_req: T::Hash[Symbol, T.untyped]
        ).returns(String)
      end
      def apply_additional_dependency_update(content, new_req, old_req)
        old_source = T.cast(old_req.fetch(:source), T::Hash[Symbol, T.untyped])
        new_source = T.cast(new_req.fetch(:source), T::Hash[Symbol, T.untyped])

        old_string = T.cast(old_source.fetch(:original_string), String)
        new_string = T.cast(new_source.fetch(:original_string), String)

        replace_additional_dependency_in_content(content, old_string, new_string)
      end

      sig do
        params(content: String, repo_url: String, old_ref: String, new_ref: String).returns(String)
      end
      def replace_ref_in_content(content, repo_url, old_ref, new_ref)
        current_repo = T.let(nil, T.nilable(String))

        updated_lines = content.lines.map do |line|
          repo_match = line.match(/^\s*-\s*repo:\s*(\S+)/)
          current_repo = repo_match[1] if repo_match

          if current_repo == repo_url &&
             line.match?(/^\s*rev:\s+#{Regexp.escape(old_ref)}(\s*(?:#.*)?)?$/)
            line.gsub(old_ref, new_ref)
          else
            line
          end
        end

        updated_lines.join
      end

      sig do
        params(content: String, old_string: String, new_string: String).returns(String)
      end
      def replace_additional_dependency_in_content(content, old_string, new_string)
        # Use line-by-line replacement to avoid variable-length look-behind issues
        # We look for the exact dependency string in various YAML formats
        escaped_old = Regexp.escape(old_string)

        updated_lines = content.lines.map do |line|
          # Check if this line contains the dependency in additional_dependencies context
          # Matches formats like:
          #   - types-requests==1.0.0
          #   - 'types-requests==1.0.0'
          #   - "types-requests==1.0.0"
          #   [..., types-requests==1.0.0, ...]
          if line.match?(/^\s*-\s*['"]?#{escaped_old}['"]?\s*$/) ||        # Block style
             line.match?(/[\[,]\s*['"]?#{escaped_old}['"]?\s*[,\]]/) ||    # Flow style
             line.match?(/^\s*-\s*['"]?#{escaped_old}['"]?\s*#/)           # With comment
            line.gsub(old_string, new_string)
          else
            line
          end
        end

        updated_lines.join
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("pre_commit", Dependabot::PreCommit::FileUpdater)
