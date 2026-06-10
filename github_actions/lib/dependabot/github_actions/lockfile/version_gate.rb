# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/github_actions/constants"
require "dependabot/github_actions/lockfile/errors"

module Dependabot
  module GithubActions
    module Lockfile
      # Guards against lockfiles whose schema major we do not support. Within a major
      # the contract is additive-only, so an unknown minor is tolerated; an unknown
      # major is a hard stop (structure may have changed enough to emit a bad lock).
      module VersionGate
        extend T::Sig

        sig { params(found: String).void }
        def self.assert_supported!(found)
          return if compatible?(found)

          raise UnsupportedLockfileVersion.new(found, SUPPORTED_LOCKFILE_VERSION)
        end

        sig { params(found: String).returns(T::Boolean) }
        def self.compatible?(found)
          return false if found.nil? || found.strip.empty?

          found_segments = segments(found)
          supported_segments = segments(SUPPORTED_LOCKFILE_VERSION)

          return false unless found_segments[0] == supported_segments[0]

          # 0.x is unstable: a minor bump may be breaking, so require an exact minor
          # match until the format reaches a stable major.
          return found_segments[1] == supported_segments[1] if supported_segments[0] == "0"

          true
        end

        sig { params(version: String).returns(T::Array[String]) }
        def self.segments(version)
          # Versions look like "v0.0.1"; drop the leading "v" and split on dots.
          version.delete_prefix("v").split(".")
        end
      end
    end
  end
end
