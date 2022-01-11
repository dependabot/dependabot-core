# frozen_string_literal: true

module Dependabot
  module DependencyUpdaters
    class Base
      def update(dependency:, requirements:, configuration:)
        raise NotImplementedError
      end
    end
  end
end
