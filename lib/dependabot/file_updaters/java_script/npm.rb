# frozen_string_literal: true

require "dependabot/file_updaters/java_script/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileUpdaters
    module JavaScript
      class Npm < Dependabot::FileUpdaters::JavaScript::Base
        LOCKFILE_NAME = "package-lock.json"
        HELPER_PATH = "helpers/npm/bin/run.js"

        def self.updated_files_regex
          [
            /^package\.json$/,
            /^package-lock\.json$/
          ]
        end

        private

        def updated_lockfile_content
          super
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise unless error.message.start_with?("No matching version found")
          raise Dependabot::DependencyFileNotResolvable, error.message
        end
      end
    end
  end
end
