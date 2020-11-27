# frozen_string_literal: true

require_relative "directives"
require_relative "base_directive"

module Dependabot
  module Cake
    module Directives
      class LoadDirective < Dependabot::Cake::Directives::BaseDirective
        def initialize(line)
          @type = "load"
          super(line)
        end

        private

        def default_scheme
          "local"
        end
      end
    end
  end
end

# rubocop:disable Layout/LineLength
Dependabot::Cake::Directives.register("load", Dependabot::Cake::Directives::LoadDirective)
Dependabot::Cake::Directives.register("l", Dependabot::Cake::Directives::LoadDirective)
# rubocop:enable Layout/LineLength
