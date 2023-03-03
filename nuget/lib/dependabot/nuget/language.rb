# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/nuget/version"
require "dependabot/ecosystem"

module Dependabot
  module Nuget
    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(language: String, raw_version: String, requirement: T.nilable(Requirement)).void }
      def initialize(language, raw_version, requirement = nil)
        super(
          name: language,
          version: Version.new(raw_version),
          requirement: requirement,
       )
      end
    end

    class CSharpLanguage < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      LANGUAGE = "CSharp"
      TYPE = "cs"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig { params(language: String, requirement: T.nilable(Requirement)).void }
      def initialize(language, requirement = nil)
        super(
          name: language,
          requirement: requirement,
       )
      end
    end

    class VBLanguage < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      LANGUAGE = "VB"
      TYPE = "vb"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig { params(language: String, requirement: T.nilable(Requirement)).void }
      def initialize(language, requirement = nil)
        super(
          name: language,
          requirement: requirement,
       )
      end
    end

    class FSharpLanguage < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      LANGUAGE = "FSharp"
      TYPE = "fs"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig { params(language: String, requirement: T.nilable(Requirement)).void }
      def initialize(language, requirement = nil)
        super(
          name: language,
          requirement: requirement,
       )
      end
    end

    class DotNet < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      TYPE = "dotnet"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig { params(language: String, requirement: T.nilable(Requirement)).void }
      def initialize(language, requirement = nil)
        super(
          name: language,
          requirement: requirement,
       )
      end
    end
  end
end
