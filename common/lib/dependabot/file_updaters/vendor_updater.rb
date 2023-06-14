# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/file_updaters/supplement_updater"

# This class is a specialisation of the SupplementUpdater which should be used
# for vendored files so any files it creates are properly flagged as relating
# to vendoring of dependencies.
#
# This flagging ensures that the Updater and other components while handle them
# correctly when compiling grouped updates.
module Dependabot
  module FileUpdaters
    class VendorUpdater < SupplementUpdater
      # This provides backwards compatability for anyone who used this class
      # before the base class was introduced and aligns the method's public
      # signatures with it's special-case domain.
      def initialize(repo_contents_path:, vendor_dir:)
        @repo_contents_path = repo_contents_path
        @vendor_dir = vendor_dir
        super(repo_contents_path: @repo_contents_path, target_directory: @vendor_dir)
      end

      alias updated_vendor_cache_files updated_files

      private

      def create_dependency_file(parameters)
        Dependabot::DependencyFile.new(**parameters.merge({ vendored_file: true }))
      end
    end
  end
end
