# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers"
require "dependabot/devbox/update_checker"

# Behaviour is exercised in later phases; for now this just asserts the class
# is wired into the update-checker registry.
RSpec.describe Dependabot::Devbox::UpdateChecker do
  it "is registered for the devbox package manager" do
    expect(Dependabot::UpdateCheckers.for_package_manager("devbox")).to eq(described_class)
  end
end
