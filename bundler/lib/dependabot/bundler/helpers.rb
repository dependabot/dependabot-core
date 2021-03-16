# frozen_string_literal: true

module Dependabot
  module Bundler
    module Helpers
      V1 = "1"
      V2 = "2"

      # TODO: Add support for bundler v2
      # return "v2" if lockfile.content.match?(/BUNDLED WITH\s+2/m)
      def self.bundler_version(_lockfile)
        V1
      end

      def self.detected_bundler_version(lockfile)
        return "unknown" unless lockfile
        return V2 if lockfile.content.match?(/BUNDLED WITH\s+2/m)

        V1
      end
    end
  end
end
