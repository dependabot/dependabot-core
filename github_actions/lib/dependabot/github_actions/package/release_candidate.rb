# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/git_tag_details"
require "dependabot/version"

module Dependabot
  module GithubActions
    module Package
      class ReleaseCandidate < T::ImmutableStruct
        extend T::Sig

        const :details, Dependabot::GitTagDetails
        const :version, Dependabot::Version
        const :release_date, T.nilable(String), default: nil

        sig do
          params(details: Dependabot::GitTagDetails, release_date: T.nilable(String)).returns(ReleaseCandidate)
        end
        def self.from_details(details, release_date: nil)
          version = details.version
          unless version.is_a?(Dependabot::Version)
            raise TypeError, "Git tag #{details.tag} must have a parsed dependency version"
          end

          new(details: details, version: version, release_date: release_date)
        end

        private_class_method :new

        sig { returns(String) }
        def tag
          details.tag
        end
      end
    end
  end
end
