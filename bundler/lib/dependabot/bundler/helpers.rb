# typed: strong
# frozen_string_literal: true

module Dependabot
  module Bundler
    module Helpers
      extend T::Sig
      extend T::Helpers

      V1 = "1"
      V2 = "2"
      # If we are updating a project with no Gemfile.lock, we default to the
      # newest version we support
      DEFAULT = V2
      BUNDLER_MAJOR_VERSION_REGEX = /BUNDLED WITH\s+(?<version>\d+)\./m
      RUBY_VERSION_REGEX = /RUBY VERSION\s+ruby\s+([^\s]+)/

      sig { params(lockfile: T.nilable(Dependabot::DependencyFile)).returns(String) }
      def self.bundler_version(lockfile)
        return DEFAULT unless lockfile

        if (matches = lockfile.content&.match(BUNDLER_MAJOR_VERSION_REGEX))
          matches[:version].to_i >= 2 ? V2 : V1
        else
          DEFAULT
        end
      end

      sig { params(lockfile: T.nilable(Dependabot::DependencyFile)).returns(String) }
      def self.detected_bundler_version(lockfile)
        return "unknown" unless lockfile

        if (matches = lockfile.content&.match(BUNDLER_MAJOR_VERSION_REGEX))
          matches[:version].to_i.to_s
        else
          "unspecified"
        end
      end
    end
  end
end
