# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Devcontainers
    class Version < Dependabot::Version
      extend T::Sig

      sig { params(other: Dependabot::Devcontainers::Version).returns(T::Boolean) }
      def same_precision?(other)
        precision == other.precision
      end

      sig { params(requirement: Dependabot::Requirement).returns(T::Boolean) }
      def satisfies?(requirement)
        requirement.satisfied_by?(self)
      end

      sig { params(other: BasicObject).returns(T.nilable(Integer)) }
      def <=>(other)
        if self == other
          precision <=> other.precision
        else
          super
        end
      end

      protected

      sig { returns(Integer) }
      def precision
        segments.size
      end
    end
  end
end

Dependabot::Utils.register_version_class("devcontainers", Dependabot::Devcontainers::Version)
