# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/devbox/helpers"

module Dependabot
  module Devbox
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      MANIFEST_FILENAME = T.let("devbox.json", String)
      LOCKFILE_FILENAME = T.let("devbox.lock", String)
      LATEST = T.let("latest", String)

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        new_manifest_content = updated_manifest_content
        if new_manifest_content != manifest.content
          updated_files << updated_file(file: manifest, content: new_manifest_content)
        end

        updated_files << lockfile_dependency_file(regenerated_lockfile_content(new_manifest_content))

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any? { |f| File.basename(f.name) == MANIFEST_FILENAME }

        raise "No devbox.json found!"
      end

      sig { returns(Dependabot::DependencyFile) }
      def manifest
        @manifest ||= T.let(
          T.must(dependency_files.find { |f| File.basename(f.name) == MANIFEST_FILENAME }),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          dependency_files.find { |f| File.basename(f.name) == LOCKFILE_FILENAME },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      # Rewrites each changed `name@constraint` entry in the raw manifest text so
      # surrounding comments/formatting survive. A `latest` constraint never
      # changes, so those entries are left untouched (lockfile-only update).
      sig { returns(String) }
      def updated_manifest_content
        content = T.must(manifest.content).dup

        dependencies.each do |dep|
          prev_reqs = (dep.previous_requirements || []).select { |r| r[:file] == manifest.name }
          new_reqs = dep.requirements.select { |r| r[:file] == manifest.name }

          prev_reqs.zip(new_reqs).each do |prev_req, new_req|
            next unless new_req

            old_constraint = prev_req[:requirement]
            new_constraint = new_req[:requirement]
            next if old_constraint.nil? || old_constraint == new_constraint

            content = content.gsub(%("#{dep.name}@#{old_constraint}"), %("#{dep.name}@#{new_constraint}"))
          end
        end

        content
      end

      # Regenerates devbox.lock by running `devbox update <pkg> --no-install`
      # (metadata-only: resolves nixpkgs commits/hashes without downloading store
      # paths) against the updated manifest in an isolated temp directory.
      sig { params(manifest_content: String).returns(String) }
      def regenerated_lockfile_content(manifest_content)
        original = lockfile&.content

        new_content =
          begin
            SharedHelpers.in_a_temporary_directory do |dir|
              dir = dir.to_s
              File.write(File.join(dir, MANIFEST_FILENAME), manifest_content)
              File.write(File.join(dir, LOCKFILE_FILENAME), original) if original
              dependencies.each do |dep|
                Helpers.run_devbox_command("update", "--no-install", dep.name, dir: dir)
              end
              File.read(File.join(dir, LOCKFILE_FILENAME))
            end
          rescue SharedHelpers::HelperSubprocessFailed, Errno::ENOENT => e
            raise Dependabot::DependencyFileNotResolvable, e.message
          end

        if original && new_content == original
          raise Dependabot::DependencyFileContentNotChanged,
                "devbox update did not change #{LOCKFILE_FILENAME}"
        end

        new_content
      end

      sig { params(content: String).returns(Dependabot::DependencyFile) }
      def lockfile_dependency_file(content)
        existing = lockfile
        return updated_file(file: existing, content: content) if existing

        Dependabot::DependencyFile.new(
          name: LOCKFILE_FILENAME,
          content: content,
          directory: manifest.directory,
          operation: Dependabot::DependencyFile::Operation::CREATE
        )
      end
    end
  end
end

Dependabot::FileUpdaters.register("devbox", Dependabot::Devbox::FileUpdater)
