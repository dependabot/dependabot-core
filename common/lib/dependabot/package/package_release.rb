# typed: strong
# frozen_string_literal: true

require "json"
require "time"
require "sorbet-runtime"
require "dependabot/package/package_language"

# Represents a single package version
module Dependabot
  module Package
    class PackageRelease
      extend T::Sig

      sig do
        params(
          version: Dependabot::Version,
          released_at: T.nilable(Time),
          latest: T::Boolean,
          yanked: T::Boolean,
          yanked_reason: T.nilable(String),
          downloads: T.nilable(Integer),
          url: T.nilable(String),
          package_type: T.nilable(String),
          language: T.nilable(Dependabot::Package::PackageLanguage)
        )
          .void
      end
      def initialize(
        version:,
        released_at: nil,
        latest: false,
        yanked: false,
        yanked_reason: nil,
        downloads: nil,
        url: nil,
        package_type: nil,
        language: nil
      )
        @version = T.let(version, Dependabot::Version)
        @released_at = T.let(released_at, T.nilable(Time))
        @latest = T.let(latest, T::Boolean)
        @yanked = T.let(yanked, T::Boolean)
        @yanked_reason = T.let(yanked_reason, T.nilable(String))
        @downloads = T.let(downloads, T.nilable(Integer))
        @url = T.let(url, T.nilable(String))
        @package_type = T.let(package_type, T.nilable(String))
        @language = T.let(language, T.nilable(Dependabot::Package::PackageLanguage))
      end

      sig { returns(Dependabot::Version) }
      attr_reader :version

      sig { returns(T.nilable(Time)) }
      attr_reader :released_at

      sig { returns(T::Boolean) }
      attr_reader :latest

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

      sig { returns(T.nilable(Dependabot::Package::PackageLanguage)) }
      attr_reader :language

      sig { returns(T::Boolean) }
      def yanked?
        @yanked
      end
    end
  end
end
