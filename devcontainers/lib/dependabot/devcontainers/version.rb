# typed: true
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Devcontainers
    class Version < Dependabot::Version
      def same_precision?(other)
        precision == other.precision
      end

      def satisfies?(requirement)
        requirement.satisfied_by?(self)
      end

      def <=>(other)
        if self == other
          precision <=> other.precision
        else
          super
        end
      end

      protected

      def precision
        segments.size
      end
    end
  end
end

Dependabot::Utils.register_version_class("devcontainers", Dependabot::Devcontainers::Version)
