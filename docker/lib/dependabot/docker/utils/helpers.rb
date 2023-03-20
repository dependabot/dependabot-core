# frozen_string_literal: true

module Dependabot
  module Docker
    module Utils
      HELM_REGEXP = /values[\-a-zA-Z_0-9]*\.ya?ml$/i

      def self.likely_helm_chart?(file)
        file.name.match?(HELM_REGEXP)
      end
    end
  end
end
