# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module GitSubmodules
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        []
      end

      def updated_dependency_files
        [updated_file(file: submodule, content: dependency.version)]
      end

      private

      def dependency
        # Git submodules will only ever be updating a single dependency
        dependencies.first
      end

      def check_required_files
        %w(.gitmodules).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end

      def submodule
        @submodule ||= dependency_files.find do |file|
          file.name == dependency.name
        end
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("submodules", Dependabot::GitSubmodules::FileUpdater)
