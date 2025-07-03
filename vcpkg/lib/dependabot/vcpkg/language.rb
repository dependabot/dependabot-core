# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/ecosystem"

module Dependabot
  module Vcpkg
    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { void }
      def initialize
        super(name: LANGUAGE)
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end
