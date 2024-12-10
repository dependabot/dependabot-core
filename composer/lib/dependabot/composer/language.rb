# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/composer/requirement"
require "dependabot/composer/version"

module Dependabot
  module Composer
    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "php"

      sig { params(raw_version: String, requirement: T.nilable(Requirement)).void }
      def initialize(raw_version, requirement: nil)
        super(
          NAME,
          Version.new(raw_version),
          Version.new(raw_version),
          [],
          [],
          requirement
       )
      end

      sig { returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end
