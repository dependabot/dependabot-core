# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module RequirementsUpdater
    module Base
      extend T::Sig
      extend T::Helpers
      extend T::Generic

      Version = type_member { { upper: Gem::Version } }
      Requirement = type_member { { upper: Gem::Requirement } }

      interface!

      sig { abstract.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements; end

      sig { abstract.returns(T::Class[Version]) }
      def version_class; end

      sig { abstract.returns(T::Class[Requirement]) }
      def requirement_class; end
    end
  end
end
