# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Julia
    module Helpers
      extend T::Sig

      JULIA_PKGMAN = "julia"
      MANIFEST_FILENAME = "Project.toml"
      LOCKFILE_FILENAME = "Manifest.toml"

      sig { params(lockfile: T.nilable(DependencyFile)).returns(T.nilable(String)) }
      def self.julia_version(lockfile)
        return nil unless lockfile

        if (match = T.must(lockfile.content).match(/julia_version\s*=\s*"(?<ver>[^"]+)"/))
          match[:ver]
        else
          warn("Unable to determine Julia version from lockfile. Please check the format.")
          nil
        end
      end
    end
  end
end
