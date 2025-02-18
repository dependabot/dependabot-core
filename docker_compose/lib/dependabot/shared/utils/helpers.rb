# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Shared
    module Utils
      HELM_REGEXP = /values[\-a-zA-Z_0-9]*\.ya?ml$/i

      extend T::Sig

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def self.likely_helm_chart?(file)
        file.name.match?(HELM_REGEXP)
      end
    end
  end
end
