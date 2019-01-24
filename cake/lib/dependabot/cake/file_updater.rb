# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Cake
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [/.*\.cake$/]
      end

      def updated_dependency_files
        # TODO
        raise NotImplementedError
      end

      private

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No Cake file!"
      end
    end
  end
end

Dependabot::FileUpdaters.register("cake", Dependabot::Cake::FileUpdater)
