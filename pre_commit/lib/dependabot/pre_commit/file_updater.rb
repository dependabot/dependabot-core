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
          .returns(T::Array[[Dependabot::DependencyRequirement, Dependabot::DependencyRequirement]])
      end
      def requirement_pairs_for_file(file)
        pairs = dependency.requirements.zip(T.must(dependency.previous_requirements))
        filtered_pairs = pairs.reject do |new_req, old_req|
          next true unless old_req

          next true if new_req.file != file.name

          new_req.source == old_req.source
        end

        filtered_pairs.map { |new_req, old_req| [new_req, T.must(old_req)] }
      end

      sig do
        params(
          content: String,
          new_req: Dependabot::DependencyRequirement,
          old_req: Dependabot::DependencyRequirement
        ).returns(String)
      end
      def apply_requirement_update(content, new_req, old_req)
        new_source = requirement_source(new_req)
        source_type = required_string_detail(new_source, :type)

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
          new_req: Dependabot::DependencyRequirement,
          old_req: Dependabot::DependencyRequirement
        ).returns(String)
      end
      def apply_git_requirement_update(content, new_req, old_req)
        new_source = requirement_source(new_req)
        old_source = requirement_source(old_req)
        repo_url = required_string_detail(old_source, :url)
        old_ref = required_string_detail(old_source, :ref)
        new_ref = required_string_detail(new_source, :ref)

        new_metadata = new_req.metadata || {}
        old_version = string_detail(new_metadata, :comment_version)
        new_version = string_detail(new_metadata, :new_comment_version)

        replace_ref_in_content(
          content,
          repo_url,
          old_ref,
          new_ref,
          old_version: old_version,
          new_version: new_version
        )
      end

      sig do
        params(
          content: String,
          new_req: Dependabot::DependencyRequirement,
          old_req: Dependabot::DependencyRequirement
        ).returns(String)
      end
      def apply_additional_dependency_update(content, new_req, old_req)
        old_source = requirement_source(old_req)
        new_source = requirement_source(new_req)

        old_string = required_string_detail(old_source, :original_string)
        new_string = required_string_detail(new_source, :original_string)

        replace_additional_dependency_in_content(content, old_string, new_string)
      end

      sig do
        params(
          requirement: Dependabot::DependencyRequirement
        ).returns(Dependabot::DependencyRequirement::Details)
      end
      def requirement_source(requirement)
        source = requirement.source
        raise KeyError, "key not found: :source" unless source

        source
      end

      sig do
        params(
          details: Dependabot::DependencyRequirement::Details,
          key: Symbol
        ).returns(String)
      end
      def required_string_detail(details, key)
        value = details.fetch(key) { details.fetch(key.to_s) }
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end

      sig do
        params(
          details: Dependabot::DependencyRequirement::Details,
          key: Symbol
        ).returns(T.nilable(String))
      end
      def string_detail(details, key)
        value = details[key] || details[key.to_s]
        value if value.is_a?(String)
      end

      sig do
        params(
          content: String,
          repo_url: String,
          old_ref: String,
          new_ref: String,
          old_version: T.nilable(String),
          new_version: T.nilable(String)
        ).returns(String)
      end
      def replace_ref_in_content(content, repo_url, old_ref, new_ref, old_version: nil, new_version: nil)
        current_repo = T.let(nil, T.nilable(String))

        updated_lines = content.lines.map do |line|
          repo_match = line.match(/^\s*-\s*repo:\s*["']?([^"'\s]+)["']?/)
          current_repo = repo_match[1] if repo_match

          if current_repo == repo_url &&
             line.match?(/^\s*rev:\s+["']?#{Regexp.escape(old_ref)}["']?(\s*(?:#.*)?)?$/)
            updated_line = line.sub(/(["']?)#{Regexp.escape(old_ref)}(["']?)/, "\\1#{new_ref}\\2")
            updated_line = update_version_comment(updated_line, old_version, new_version)
            updated_line
          else
            line
          end
        end

        updated_lines.join
      end

      sig do
        params(
          line: String,
          old_version: T.nilable(String),
          new_version: T.nilable(String)
        ).returns(String)
      end
      def update_version_comment(line, old_version, new_version)
        return line unless old_version && new_version

        pattern = /
          (                # 1: comment prefix
            \#\s*          # '#' and optional whitespace
            (?:frozen:\s*)? # optional 'frozen:' label
          )
          #{Regexp.escape(old_version)} # the old version
          (.*)$            # 2: trailing content (whitespace or other characters) up to end of line
        /x

        line.sub(pattern, "\\1#{new_version}\\2")
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
          # - types-requests==1.0.0
          # - 'types-requests==1.0.0'
          # - "types-requests==1.0.0"
          # [..., types-requests==1.0.0, ...]
          if line.match?(/^\s*-\s*['"]?#{escaped_old}['"]?\s*$/) || # Block style
             line.match?(/[\[,]\s*['"]?#{escaped_old}['"]?\s*[,\]]/) || # Flow style
             line.match?(/^\s*-\s*['"]?#{escaped_old}['"]?\s*#/) # With comment
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
