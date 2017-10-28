# frozen_string_literal: true

require "dependabot/update_checkers/java_script/yarn"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class Npm < Dependabot::UpdateCheckers::JavaScript::Yarn
        # Identical logic to Yarn, since we're just talking about the
        # package.json here, and neither npm nor Yarn use a resolver by default
      end
    end
  end
end
