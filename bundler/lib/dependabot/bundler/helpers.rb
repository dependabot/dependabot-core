# frozen_string_literal: true

module Dependabot
  module Bundler
    module Helpers
      V1 = "1.17.3"
      V2 = "2.3.9"
      # If we are updating a project with no Gemfile.lock, we default to the
      # newest version we support
      DEFAULT = V2
      # If we are updating a project with a Gemfile.lock that does not specify
      # the version it was bundled with, with failover to V1 on the assumption
      # it was created with an old version that didn't add this information
      FAILOVER = V1

      BUNDLER_MAJOR_VERSION_REGEX = /BUNDLED WITH\s+(?<version>\d+)\./m.freeze

      def self.bundler_version(lockfile)
        return DEFAULT unless lockfile

        if (matches = lockfile.content.match(BUNDLER_MAJOR_VERSION_REGEX))
          matches[:version].to_i >= 2 ? V2 : V1
        else
          FAILOVER
        end
      end

      def self.detected_bundler_version(lockfile)
        return "unknown" unless lockfile

        if (matches = lockfile.content.match(BUNDLER_MAJOR_VERSION_REGEX))
          matches[:version]
        else
          "1"
        end
      end
    end
  end
end
