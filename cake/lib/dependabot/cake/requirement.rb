# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/nuget/requirement"

# rubocop:disable Layout/LineLength
Dependabot::Utils.register_requirement_class("cake", Dependabot::Nuget::Requirement)
# rubocop:enable Layout/LineLength
