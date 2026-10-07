# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_requirement"

module Dependabot
  module RequirementsUpdater
    module Base
      extend T::Sig
      extend T::Helpers
      extend T::Generic

      Version = type_member { { upper: Gem::Version } }
      Requirement = type_member { { upper: Gem::Requirement } }

      interface!

      sig { abstract.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements; end

      private

      sig { abstract.returns(T::Class[Version]) }
      def version_class; end

      sig { abstract.returns(T::Class[Requirement]) }
      def requirement_class; end
    end
  end
end
