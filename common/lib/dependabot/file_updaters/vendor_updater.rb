# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/file_updaters/artifact_updater"

# This class is a specialisation of the ArtifactUpdater which should be used
# for vendored files so any DependencyFile objects it creates are properly
# flagged.
#
# This flagging ensures that the Updater will handle them correctly when
# compiling grouped updates.
module Dependabot
  module FileUpdaters
    class VendorUpdater < ArtifactUpdater
      extend T::Sig
      extend T::Helpers

      # This provides backwards compatibility for anyone who used this class
      # before the base ArtifactUpdater class was introduced and aligns the
      # method's public signatures with it's special-case domain.
      sig { params(repo_contents_path: T.nilable(String), vendor_dir: T.nilable(String)).void }
      def initialize(repo_contents_path:, vendor_dir:)
        @repo_contents_path = repo_contents_path
        @vendor_dir = vendor_dir
        super(repo_contents_path: @repo_contents_path, target_directory: @vendor_dir)
      end

      T.unsafe(self).alias_method :updated_vendor_cache_files, :updated_files

      private

      # VendorUpdater always flags files as vendored, so it accepts but ignores
      # the vendored_file argument. The parameter must stay to keep the override
      # signature compatible with ArtifactUpdater#create_dependency_file.
      sig do
        override
          .params(
            name: String,
            content: T.nilable(String),
            directory: String,
            type: String,
            support_file: T::Boolean,
            vendored_file: T::Boolean,
            symlink_target: T.nilable(String),
            content_encoding: String,
            deleted: T::Boolean,
            operation: String,
            mode: T.nilable(String)
          )
          .returns(Dependabot::DependencyFile)
      end
      def create_dependency_file(
        name:,
        content: nil,
        directory: "/",
        type: "file",
        support_file: false,
        vendored_file: false, # rubocop:disable Lint/UnusedMethodArgument
        symlink_target: nil,
        content_encoding: Dependabot::DependencyFile::ContentEncoding::UTF_8,
        deleted: false,
        operation: Dependabot::DependencyFile::Operation::UPDATE,
        mode: nil
      )
        super(
          name: name,
          content: content,
          directory: directory,
          type: type,
          support_file: support_file,
          vendored_file: true,
          symlink_target: symlink_target,
          content_encoding: content_encoding,
          deleted: deleted,
          operation: operation,
          mode: mode
        )
      end
    end
  end
end
