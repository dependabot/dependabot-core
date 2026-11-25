# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Python
    module RequirementReferences
      # These intentionally conservative patterns are used only before the Python helper can run, to fetch
      # possible local requirement files. They do not define pip execution semantics.
      CHILD_REQUIREMENT_REGEX = /^-r\s?(?<path>.*\.(?:txt|in))/
      CONSTRAINT_REGEX = /^-c\s?(?<path>.*\.(?:txt|in))/
    end
  end
end
