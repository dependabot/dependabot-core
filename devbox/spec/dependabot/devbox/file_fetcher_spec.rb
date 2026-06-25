# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_fetchers"
require "dependabot/devbox/file_fetcher"

# Behaviour is exercised in later phases; for now this just asserts the class
# is wired into the file-fetcher registry.
RSpec.describe Dependabot::Devbox::FileFetcher do
  it "is registered for the devbox package manager" do
    expect(Dependabot::FileFetchers.for_package_manager("devbox")).to eq(described_class)
  end
end
