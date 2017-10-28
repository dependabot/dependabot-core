# frozen_string_literal: true

require "dependabot/file_updaters/java_script/base"
require "dependabot/shared_helpers"

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
      end
    end
  end
end
