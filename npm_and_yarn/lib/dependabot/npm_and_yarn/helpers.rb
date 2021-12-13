# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    module Helpers
      def self.npm_version(lockfile_content)
        return "npm7" unless lockfile_content
        return "npm7" if JSON.parse(lockfile_content)["lockfileVersion"] == 3
        return "npm7" if JSON.parse(lockfile_content)["lockfileVersion"] == 2

        "npm6"
      rescue JSON::ParserError
        "npm6"
      end
    end
  end
end
