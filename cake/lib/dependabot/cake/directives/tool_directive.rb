# frozen_string_literal: true

require_relative "directives"
require_relative "base_directive"

module Dependabot
  module Cake
    module Directives
      class ToolDirective < Dependabot::Cake::Directives::BaseDirective
        def initialize(line)
          @type = "tool"
          super(line)
        end

        private

        def default_scheme
          "nuget"
        end
      end
    end
  end
end

# rubocop:disable Layout/LineLength
Dependabot::Cake::Directives.register("tool", Dependabot::Cake::Directives::ToolDirective)
# rubocop:enable Layout/LineLength
