# frozen_string_literal: true

module Dependabot
  module Bundler
    module Helpers
      V1 = "1"
      V2 = "2"

      def self.bundler_version(_lockfile)
        return V2 if lockfile.content.match?(/BUNDLED WITH\s+2/m)

        V1
      end
    end
  end
end
