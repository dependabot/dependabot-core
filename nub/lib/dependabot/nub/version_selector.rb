# typed: strong
# frozen_string_literal: true

require "dependabot/npm_and_yarn/version_selector"

# Engine-constraint selection is format-agnostic; delegate to npm_and_yarn.
module Dependabot
  module Nub
    VersionSelector = Dependabot::NpmAndYarn::VersionSelector
  end
end
