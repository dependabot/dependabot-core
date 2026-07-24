# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/github_actions/constants"
require "dependabot/github_actions/lockfile/errors"

module Dependabot
  module GithubActions
    module Lockfile
      # Pre-1.0 lockfile schema revisions may be breaking, so only the explicitly
      # supported version is safe to read and rewrite.
      module VersionGate
        extend T::Sig

        sig { params(found: String).void }
        def self.assert_supported!(found)
          return if compatible?(found)

          raise UnsupportedLockfileVersion.new(found, SUPPORTED_LOCKFILE_VERSION)
        end

        sig { params(found: String).returns(T::Boolean) }
        def self.compatible?(found)
          found == SUPPORTED_LOCKFILE_VERSION
        end
      end
    end
  end
end
