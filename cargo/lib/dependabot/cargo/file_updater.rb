# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/errors"
require "dependabot/git_commit_checker"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module Cargo
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      TABLE_HEADER = /\A[ \t]*\[/
      WORKSPACE_DEPENDENCY_TABLE = /\A[ \t]*\[workspace\.dependencies(\.|\])/

      require_relative "file_updater/manifest_updater"
      require_relative "file_updater/lockfile_updater"
      require_relative "file_updater/workspace_manifest_updater"

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        # Returns an array of updated files. Only files that have been updated
        # should be returned.
        updated_files = []

        manifest_files.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(
              file: file,
              content: updated_manifest_content(file)
            )
        end

        if lockfile && updated_lockfile_content != T.must(lockfile).content
          updated_files <<
            updated_file(file: T.must(lockfile), content: updated_lockfile_content)
        end

        raise "No files changed!" if updated_files.empty?

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        raise "No Cargo.toml!" unless get_original_file("Cargo.toml")
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_manifest_content(file)
        return workspace_root_manifest_content(file) if workspace_root_manifest?(file)

        ManifestUpdater.new(
          dependencies: dependencies,
          manifest: file
        ).updated_manifest_content
      end

      # A workspace root can also be a package in its own right, carrying its own
      # [dependencies] alongside [workspace.dependencies]. Updating only the workspace
      # table leaves the root behind while members move, resolving to two versions of
      # the same crate.
      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def workspace_root_manifest_content(file)
        content = WorkspaceManifestUpdater.new(
          dependencies: dependencies,
          manifest: file
        ).updated_manifest_content

        dependencies
          .select { |dep| package_requirement_changed?(file, dep) }
          .reduce(content) { |current, dep| apply_package_update(file, dep, current) }
      end

      # Applied one dependency at a time: ManifestUpdater folds them together and raises
      # mid-fold, which would discard the updates already applied to the others.
      sig do
        params(file: Dependabot::DependencyFile, dep: Dependabot::Dependency, content: String)
          .returns(String)
      end
      def apply_package_update(file, dep, content)
        # ManifestUpdater matches `[dependencies.<name>]` with an unanchored regex, which
        # also matches `[workspace.dependencies.<name>]`. That table has already been
        # updated, so leaving it visible makes the matcher settle on it and conclude there
        # is nothing to change. Hide it for this pass and put it back afterwards.
        masked, masked_lines = mask_workspace_dependencies(content)

        updated = ManifestUpdater.new(
          dependencies: [dep],
          manifest: updated_file(file: file, content: masked)
        ).updated_manifest_content

        restore_masked_lines(updated, content, masked_lines)
      rescue Dependabot::DependencyFileContentNotChanged
        # Keep what we have rather than failing the job: a partial update beats no pull
        # request.
        Dependabot.logger.warn(
          "could not update #{dep.name} in #{file.name}; keeping the workspace-level update only"
        )
        content
      end

      # Replaces every line of a [workspace.dependencies] table with a comment, returning
      # the masked content and the indices that were masked.
      sig { params(content: String).returns([String, T::Array[Integer]]) }
      def mask_workspace_dependencies(content)
        in_workspace_table = T.let(false, T::Boolean)
        masked_lines = T.let([], T::Array[Integer])

        lines = content.lines.each_with_index.map do |line, index|
          in_workspace_table = line.match?(WORKSPACE_DEPENDENCY_TABLE) if line.match?(TABLE_HEADER)
          next line unless in_workspace_table

          masked_lines << index
          "#" + (line.end_with?("\r\n") ? "\r\n" : "\n")
        end

        [lines.join, masked_lines]
      end

      # ManifestUpdater only substitutes within lines, so the masked lines are still at
      # their original indices and can be put back verbatim.
      sig { params(updated: String, original: String, masked_lines: T::Array[Integer]).returns(String) }
      def restore_masked_lines(updated, original, masked_lines)
        updated_lines = updated.lines
        original_lines = original.lines
        raise Dependabot::DependencyFileContentNotChanged unless updated_lines.length == original_lines.length

        masked_lines.each { |index| updated_lines[index] = T.must(original_lines[index]) }
        updated_lines.join
      end

      # Does this dependency have a changed requirement in one of `file`'s own package
      # dependency tables, as opposed to [workspace.dependencies]?
      sig { params(file: Dependabot::DependencyFile, dep: Dependabot::Dependency).returns(T::Boolean) }
      def package_requirement_changed?(file, dep)
        previous_requirements = dep.previous_requirements
        return false if previous_requirements.nil?

        (dep.requirements - previous_requirements).any? do |req|
          req[:file] == file.name && !req[:groups]&.include?("workspace.dependencies")
        end
      end

      sig { returns(String) }
      def updated_lockfile_content
        @updated_lockfile_content ||= T.let(
          LockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ).updated_lockfile_content,
          T.nilable(String)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def manifest_files
        @manifest_files ||= T.let(
          dependency_files
          .select { |f| f.name.end_with?("Cargo.toml") }
          .reject(&:support_file?),
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(get_original_file("Cargo.lock"), T.nilable(Dependabot::DependencyFile))
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def workspace_root_manifest?(file)
        return false unless file.name == "Cargo.toml"

        parsed_file = TomlRB.parse(file.content)
        parsed_file.key?("workspace") && parsed_file["workspace"].key?("dependencies")
      rescue TomlRB::ParseError
        false
      end
    end
  end
end

Dependabot::FileUpdaters.register("cargo", Dependabot::Cargo::FileUpdater)
