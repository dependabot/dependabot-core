# typed: strong
# frozen_string_literal: true

require "json"
require "time"
require "sorbet-runtime"

# Represents a single package version
module Dependabot
  module Python
    module Package
      class PackageLanguage
        extend T::Sig

        sig do
          params(
            name: String,
            version: T.nilable(Dependabot::Version),
            requirement: T.nilable(Dependabot::Requirement)
          ).void
        end
        def initialize(name:, version: nil, requirement: nil)
          @name = T.let(name, String)
          @version = T.let(version, T.nilable(Dependabot::Version))
          @requirement = T.let(requirement, T.nilable(Dependabot::Requirement))
        end

        sig { returns(String) }
        attr_reader :name

        sig { returns(T.nilable(Dependabot::Version)) }
        attr_reader :version

        sig { returns(T.nilable(Dependabot::Requirement)) }
        attr_reader :requirement

        sig { params(args: T.untyped).returns(String) }
        def to_json(*args) # rubocop:disable Lint/UnusedMethodArgument
          {
            name: @name,
            version: @version,
            requirement: @requirement
          }.to_json
        end
      end

      class PackageRelease
        extend T::Sig

        sig do
          params(
            version: Dependabot::Version,
            released_at: T.nilable(Time),
            yanked: T::Boolean,
            yanked_reason: T.nilable(String),
            downloads: T.nilable(Integer),
            url: T.nilable(String),
            package_type: T.nilable(String),
            language: T.nilable(Dependabot::Python::Package::PackageLanguage)
          )
            .void
        end
        def initialize(
          version:,
          released_at: nil,
          yanked: false,
          yanked_reason: nil,
          downloads: nil,
          url: nil,
          package_type: nil,
          language: nil
        )
          @version = T.let(version, Dependabot::Version)
          @released_at = T.let(released_at, T.nilable(Time))
          @yanked = T.let(yanked, T::Boolean)
          @yanked_reason = T.let(yanked_reason, T.nilable(String))
          @downloads = T.let(downloads, T.nilable(Integer))
          @url = T.let(url, T.nilable(String))
          @package_type = T.let(package_type, T.nilable(String))
          @language = T.let(language, T.nilable(Dependabot::Python::Package::PackageLanguage))
        end

        sig { returns(Dependabot::Version) }
        attr_reader :version

        sig { returns(T.nilable(Time)) }
        attr_reader :released_at

        sig { returns(T::Boolean) }
        attr_reader :yanked

        sig { returns(T.nilable(String)) }
        attr_reader :yanked_reason

        sig { returns(T.nilable(Integer)) }
        attr_reader :downloads

        sig { returns(T.nilable(String)) }
        attr_reader :url

        sig { returns(T.nilable(String)) }
        attr_reader :package_type

        sig { returns(T.nilable(Dependabot::Python::Package::PackageLanguage)) }
        attr_reader :language

        sig { returns(T::Boolean) }
        def yanked?
          @yanked
        end

        sig { params(args: T.untyped).returns(String) }
        def to_json(*args) # rubocop:disable Lint/UnusedMethodArgument
          {
            version: @version.to_s,
            released_at: @released_at,
            yanked: @yanked,
            yanked_reason: @yanked_reason,
            downloads: @downloads,
            url: @url,
            package_type: @package_type,
            language: @language
          }.to_json
        end
      end
    end
  end
end
