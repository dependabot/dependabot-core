# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/helm"
require "dependabot/helm/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Helm::UpdateChecker do
  it_behaves_like "a dependency update checker"
end
