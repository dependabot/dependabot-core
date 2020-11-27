# frozen_string_literal: true

require_relative "directives"
require_relative "base_directive"

module Dependabot
  module Cake
    module Directives
      class ModuleDirective < Dependabot::Cake::Directives::BaseDirective
        def initialize(line)
          @type = "module"
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
Dependabot::Cake::Directives.register("module", Dependabot::Cake::Directives::ModuleDirective)
# rubocop:enable Layout/LineLength
