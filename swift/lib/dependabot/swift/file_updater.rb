# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        raise NotImplementedError
      end

      def updated_dependency_files
        raise NotImplementedError
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("swift", Dependabot::Swift::FileUpdater)
