# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/composer/version"

module Dependabot
  module Composer
    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "php"

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          NAME,
          Version.new(raw_version),
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
