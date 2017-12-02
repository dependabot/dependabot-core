# frozen_string_literal: true

require "dependabot/file_updaters/java_script/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileUpdaters
    module JavaScript
      class Yarn < Dependabot::FileUpdaters::JavaScript::Base
        LOCKFILE_NAME = "yarn.lock"
        HELPER_PATH = "helpers/yarn/bin/run.js"

        def self.updated_files_regex
          [
            /^package\.json$/,
            /^yarn\.lock$/
          ]
        end

        private

        def updated_lockfile_content
          super
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise unless error.message.start_with?("Couldn't find any versions")
          raise Dependabot::DependencyFileNotResolvable, error.message
        end
      end
    end
  end
end
