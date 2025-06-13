# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia"

RSpec.describe Dependabot::Julia do
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
