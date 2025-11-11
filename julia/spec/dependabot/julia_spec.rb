# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Julia do
  it_behaves_like "it registers the required classes", "julia"

  it "has a version number" do
    expect(Dependabot::Julia::VERSION).not_to be_nil
  end

  describe ".file_updater_class" do
    subject(:file_updater_class) { described_class.file_updater_class }

    it "returns the FileUpdater class" do
      expect(file_updater_class).to eq(Dependabot::Julia::FileUpdater)
    end
  end

  # Other integration tests for the Julia module can go here
end
