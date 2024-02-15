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

      sig do
        override
          .params(parameters: T::Hash[Symbol, T.untyped])
          .returns(Dependabot::DependencyFile)
      end
      def create_dependency_file(parameters)
        Dependabot::DependencyFile.new(**T.unsafe({ **parameters.merge({ vendored_file: true }) }))
      end
    end
  end
end
