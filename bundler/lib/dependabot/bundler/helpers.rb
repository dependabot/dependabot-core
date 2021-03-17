# frozen_string_literal: true

module Dependabot
  module Bundler
    module Helpers
      V1 = "1"
      V2 = "2"

      # NOTE: options is a manditory argument to ensure we pass it from all calling classes
      def self.bundler_version(lockfile, options:)
        # For now, force V2 if bundler_2_available
        return V2 if options[:bundler_2_available]
        return V1 unless lockfile

        # TODO: Add support for bundler v2 based on lockfile
        return V2 if lockfile.content.match?(/BUNDLED WITH\s+2/m)

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
