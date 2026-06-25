# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/metadata_finders"
require "dependabot/devbox/metadata_finder"

# Behaviour is exercised in later phases; for now this just asserts the class
# is wired into the metadata-finder registry.
RSpec.describe Dependabot::Devbox::MetadataFinder do
  it "is registered for the devbox package manager" do
    expect(Dependabot::MetadataFinders.for_package_manager("devbox")).to eq(described_class)
  end
end
