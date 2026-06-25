# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_updaters"
require "dependabot/devbox/file_updater"

# Behaviour is exercised in later phases; for now this just asserts the class
# is wired into the file-updater registry.
RSpec.describe Dependabot::Devbox::FileUpdater do
  it "is registered for the devbox package manager" do
    expect(Dependabot::FileUpdaters.for_package_manager("devbox")).to eq(described_class)
  end
end
