# frozen_string_literal: true

require "dependabot/file_updaters/java_script/base"
require "dependabot/shared_helpers"

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
      end
    end
  end
end
